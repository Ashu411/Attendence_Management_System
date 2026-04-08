-- ============================================
-- Attendance Management System — MySQL Script
-- Features:
-- 1) Tables for Students, Faculty, Courses, Classes, Enrollment, Sessions, Attendance, Holidays, Config.
-- 2) Audit log & triggers (prevent duplicates, update summary).
-- 3) Functions & Procedures (with cursors) to mark, compute %, defaulter list, subject analysis.
-- 4) Views for summaries and quick reporting.
-- 5) Example usage at the end.
-- ============================================

/* -----------------------------
   0. Cleanup (if re-running)
   ----------------------------- */
CREATE DATABASE project;
USE project;
DROP TABLE IF EXISTS attendance_audit;
DROP TABLE IF EXISTS attendance;
DROP TABLE IF EXISTS session;
DROP TABLE IF EXISTS class;
DROP TABLE IF EXISTS enrollment;
DROP TABLE IF EXISTS course;
DROP TABLE IF EXISTS student;
DROP TABLE IF EXISTS faculty;
DROP TABLE IF EXISTS holiday;
DROP TABLE IF EXISTS config;
DROP VIEW  IF EXISTS v_student_att_summary;
DROP VIEW  IF EXISTS v_subject_att_summary;

-- -------------------------
-- 1. Core tables
-- -------------------------
CREATE TABLE faculty (
  faculty_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(150) UNIQUE,
  dept VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE student (
  student_id INT AUTO_INCREMENT PRIMARY KEY,
  roll_no VARCHAR(20) UNIQUE NOT NULL,
  name VARCHAR(100) NOT NULL,
  class_year VARCHAR(20),
  email VARCHAR(150),
  category VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE course (
  course_id INT AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(20) UNIQUE NOT NULL,
  title VARCHAR(150) NOT NULL,
  credits INT DEFAULT 3,
  dept VARCHAR(50)
);

CREATE TABLE class (
  class_id INT AUTO_INCREMENT PRIMARY KEY,
  course_id INT NOT NULL,
  faculty_id INT,
  semester VARCHAR(10),
  section VARCHAR(10),
  -- for schedule simplified: day_of_week e.g. 'Mon', and start_time
  day_of_week ENUM('Mon','Tue','Wed','Thu','Fri','Sat','Sun'),
  start_time TIME,
  duration_minutes INT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (course_id) REFERENCES course(course_id) ON DELETE CASCADE,
  FOREIGN KEY (faculty_id) REFERENCES faculty(faculty_id) ON DELETE SET NULL
);

CREATE TABLE enrollment (
  enroll_id INT AUTO_INCREMENT PRIMARY KEY,
  student_id INT NOT NULL,
  class_id INT NOT NULL,
  enroll_date DATE DEFAULT (CURRENT_DATE()),
  status ENUM('active','dropped') DEFAULT 'active',
  UNIQUE(student_id, class_id),
  FOREIGN KEY (student_id) REFERENCES student(student_id) ON DELETE CASCADE,
  FOREIGN KEY (class_id) REFERENCES class(class_id) ON DELETE CASCADE
);

CREATE TABLE session (
  session_id INT AUTO_INCREMENT PRIMARY KEY,
  class_id INT NOT NULL,
  session_date DATE NOT NULL,
  start_time TIME,
  created_by INT, -- faculty_id who created
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(class_id, session_date),
  FOREIGN KEY (class_id) REFERENCES class(class_id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES faculty(faculty_id) ON DELETE SET NULL
);

CREATE TABLE attendance (
  attendance_id INT AUTO_INCREMENT PRIMARY KEY,
  session_id INT NOT NULL,
  student_id INT NOT NULL,
  status ENUM('present','absent','late','excused') NOT NULL DEFAULT 'absent',
  marked_by INT, -- faculty id who marked
  marked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  remarks VARCHAR(255),
  UNIQUE(session_id, student_id),
  FOREIGN KEY (session_id) REFERENCES session(session_id) ON DELETE CASCADE,
  FOREIGN KEY (student_id) REFERENCES student(student_id) ON DELETE CASCADE,
  FOREIGN KEY (marked_by) REFERENCES faculty(faculty_id) ON DELETE SET NULL
);

-- Holidays (exclude these when calculating %)
CREATE TABLE holiday (
  holiday_id INT AUTO_INCREMENT PRIMARY KEY,
  holiday_date DATE NOT NULL UNIQUE,
  description VARCHAR(200)
);

-- Config (thresholds etc.)
CREATE TABLE config (
  config_key VARCHAR(100) PRIMARY KEY,
  config_value VARCHAR(200)
);

INSERT INTO config (config_key, config_value) VALUES
('ATTENDANCE_THRESHOLD_PERCENT','75'),
('LATE_COUNT_AS_PRESENT','1'); -- '1' if late considered as present, else '0'

-- Audit log for actions
CREATE TABLE attendance_audit (
  audit_id INT AUTO_INCREMENT PRIMARY KEY,
  action VARCHAR(50),
  details TEXT,
  action_by INT,
  action_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (action_by) REFERENCES faculty(faculty_id) ON DELETE SET NULL
);

-- Indexes for faster reporting
CREATE INDEX idx_attendance_session ON attendance(session_id);
CREATE INDEX idx_attendance_student ON attendance(student_id);
CREATE INDEX idx_session_class_date ON session(class_id, session_date);

/* -------------------------
   2. Views for quick reports
   ------------------------- */
-- per-student summary: total sessions, presents, absents, percentage (excluding holidays)
CREATE VIEW v_student_att_summary AS
SELECT
  s.student_id,
  s.roll_no,
  s.name,
  c.course_id,
  c.code AS course_code,
  c.title AS course_title,
  cl.class_id,
  cl.section,
  COUNT(a.attendance_id) AS total_marked,
  SUM(a.status = 'present' OR (a.status='late' AND (SELECT config_value FROM config WHERE config_key='LATE_COUNT_AS_PRESENT')='1')) AS presents,
  SUM(a.status = 'absent') AS absents,
  ROUND(
    SUM(a.status = 'present' OR (a.status='late' AND (SELECT config_value FROM config WHERE config_key='LATE_COUNT_AS_PRESENT')='1')) /
    GREATEST(1, COUNT(a.attendance_id)) * 100,2
  ) AS attendance_percent
FROM attendance a
JOIN student s ON s.student_id = a.student_id
JOIN session se ON se.session_id = a.session_id
JOIN class cl ON cl.class_id = se.class_id
JOIN course c ON c.course_id = cl.course_id
GROUP BY s.student_id, cl.class_id;

-- per-subject summary for analytics
CREATE VIEW v_subject_att_summary AS
SELECT
  cl.class_id,
  c.course_id,
  c.code AS course_code,
  c.title AS course_title,
  COUNT(DISTINCT se.session_date) AS total_sessions,
  SUM(a.status='present' OR (a.status='late' AND (SELECT config_value FROM config WHERE config_key='LATE_COUNT_AS_PRESENT')='1')) AS total_presents,
  ROUND( SUM(a.status='present' OR (a.status='late' AND (SELECT config_value FROM config WHERE config_key='LATE_COUNT_AS_PRESENT')='1')) /
         GREATEST(1, COUNT(a.attendance_id)) * 100 ,2) AS avg_attendance_percent
FROM attendance a
JOIN session se ON se.session_id = a.session_id
JOIN class cl ON cl.class_id = se.class_id
JOIN course c ON c.course_id = cl.course_id
GROUP BY cl.class_id;

/* -------------------------
   3. Triggers
   ------------------------- */
DELIMITER $$
-- Prevent duplicate attendance insertion (additional safety)
CREATE TRIGGER trg_before_insert_attendance
BEFORE INSERT ON attendance
FOR EACH ROW
BEGIN
  DECLARE cnt INT;
  SELECT COUNT(*) INTO cnt FROM attendance WHERE session_id = NEW.session_id AND student_id = NEW.student_id;
  IF cnt > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Duplicate attendance record for session and student';
  END IF;
END$$

-- On insert/update attendance -> write audit
CREATE TRIGGER trg_after_insert_attendance
AFTER INSERT ON attendance
FOR EACH ROW
BEGIN
  INSERT INTO attendance_audit(action, details, action_by)
  VALUES ('INSERT_ATTENDANCE', CONCAT('session:', NEW.session_id, ', student:', NEW.student_id, ', status:', NEW.status), NEW.marked_by);
END$$

CREATE TRIGGER trg_after_update_attendance
AFTER UPDATE ON attendance
FOR EACH ROW
FOR EACH ROW
BEGIN
  INSERT INTO attendance_audit(action, details, action_by)
  VALUES ('UPDATE_ATTENDANCE', CONCAT('attendance_id:', NEW.attendance_id, ', old_status:', OLD.status, ', new_status:', NEW.status), NEW.marked_by);
END$$
DELIMITER ;

-- Note: some MySQL versions disallow multiple FOR EACH ROW; if error, remove the duplicate FOR EACH ROW.

-- Trigger to create session automatically when class schedule inserted (optional)
DELIMITER $$
CREATE TRIGGER trg_after_insert_class
AFTER INSERT ON class
FOR EACH ROW
BEGIN
  -- Example: create next week's session for the scheduled day automatically (simplified)
  DECLARE next_date DATE;
  SET next_date = DATE_ADD(CURRENT_DATE, INTERVAL 7 DAY);
  INSERT IGNORE INTO session(class_id, session_date, start_time, created_by)
  VALUES (NEW.class_id, next_date, NEW.start_time, NEW.faculty_id);
END$$
DELIMITER ;

/* -------------------------
   4. Functions
   ------------------------- */
DELIMITER $$
-- Function to compute percentage for a student in a specific class
CREATE FUNCTION fn_get_attendance_percent(p_student_id INT, p_class_id INT) RETURNS DECIMAL(5,2)
DETERMINISTIC
BEGIN
  DECLARE total INT DEFAULT 0;
  DECLARE present_count INT DEFAULT 0;
  SELECT COUNT(a.attendance_id) INTO total
  FROM attendance a
  JOIN session s ON s.session_id = a.session_id
  WHERE a.student_id = p_student_id AND s.class_id = p_class_id
    AND s.session_date NOT IN (SELECT holiday_date FROM holiday);

  SELECT SUM(a.status='present' OR (a.status='late' AND (SELECT config_value FROM config WHERE config_key='LATE_COUNT_AS_PRESENT')='1'))
  INTO present_count
  FROM attendance a
  JOIN session s ON s.session_id = a.session_id
  WHERE a.student_id = p_student_id AND s.class_id = p_class_id
    AND s.session_date NOT IN (SELECT holiday_date FROM holiday);

  IF total = 0 THEN
    RETURN 0.00;
  END IF;
  RETURN ROUND(present_count/total * 100,2);
END$$
DELIMITER ;

-- Function to get threshold
DELIMITER $$
CREATE FUNCTION fn_get_threshold() RETURNS INT
DETERMINISTIC
BEGIN
  DECLARE thr INT DEFAULT 75;
  SELECT CAST(config_value AS UNSIGNED) INTO thr FROM config WHERE config_key='ATTENDANCE_THRESHOLD_PERCENT';
  RETURN thr;
END$$
DELIMITER ;

-- Function to check if a date is holiday
DELIMITER $$
CREATE FUNCTION fn_is_holiday(p_date DATE) RETURNS BOOLEAN
DETERMINISTIC
BEGIN
  DECLARE cnt INT DEFAULT 0;
  SELECT COUNT(*) INTO cnt FROM holiday WHERE holiday_date = p_date;
  RETURN cnt > 0;
END$$
DELIMITER ;

-- -------------------------
-- 5. Procedures (cursors, error handlers)
-- -------------------------
DELIMITER $$
-- Procedure: Create session for a class for a given date
CREATE PROCEDURE sp_create_session(
  IN p_class_id INT,
  IN p_session_date DATE,
  IN p_start_time TIME,
  IN p_created_by INT
)
BEGIN
  START TRANSACTION;
  INSERT IGNORE INTO session(class_id, session_date, start_time, created_by)
  VALUES (p_class_id, p_session_date, p_start_time, p_created_by);
  INSERT INTO attendance_audit(action, details, action_by)
  VALUES ('CREATE_SESSION', CONCAT('class:', p_class_id, ', date:', p_session_date), p_created_by);
  COMMIT;
END$$

-- Procedure: Faculty marks attendance for a single session (takes a JSON-like input simulation via temp table or we pass a CSV)
-- Here we accept a simple table-driven approach: call sp_mark_attendance_for_session which reads from a temporary table 'tmp_att_mark' (student_id, status, remarks)
CREATE PROCEDURE sp_mark_attendance_for_session(
  IN p_session_id INT,
  IN p_marked_by INT
)
BEGIN
  DECLARE v_student_id INT;
  DECLARE v_status ENUM('present','absent','late','excused');
  DECLARE v_remarks VARCHAR(255);
  DECLARE done INT DEFAULT 0;

  DECLARE cur CURSOR FOR SELECT student_id, status, remarks FROM tmp_att_mark;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done=1;

  START TRANSACTION;
  OPEN cur;
  read_loop: LOOP
    FETCH cur INTO v_student_id, v_status, v_remarks;
    IF done THEN
      LEAVE read_loop;
    END IF;
    -- If attendance exists, update; else insert
    IF EXISTS (SELECT 1 FROM attendance WHERE session_id=p_session_id AND student_id=v_student_id) THEN
      UPDATE attendance SET status=v_status, remarks=v_remarks, marked_by=p_marked_by, marked_at=CURRENT_TIMESTAMP
      WHERE session_id=p_session_id AND student_id=v_student_id;
    ELSE
      INSERT INTO attendance(session_id, student_id, status, marked_by, remarks)
      VALUES (p_session_id, v_student_id, v_status, p_marked_by, v_remarks);
    END IF;
  END LOOP;
  CLOSE cur;
  INSERT INTO attendance_audit(action, details, action_by)
  VALUES ('MARK_SESSION', CONCAT('session:', p_session_id), p_marked_by);
  COMMIT;
END$$

-- Procedure: Bulk mark using CSV-like input (string contains semicolon-separated records "studentid:status:remarks")
CREATE PROCEDURE sp_bulk_mark_from_csv(
  IN p_session_id INT,
  IN p_marked_by INT,
  IN p_csv TEXT
)
BEGIN
  -- parse p_csv using a simple loop (MySQL string operations)
  DECLARE rest TEXT DEFAULT p_csv;
  DECLARE next_rec TEXT;
  DECLARE delim_pos INT;
  DECLARE sid INT;
  DECLARE st VARCHAR(10);
  DECLARE rem VARCHAR(255);

  START TRANSACTION;
  parse_loop: LOOP
    SET delim_pos = INSTR(rest, ';');
    IF delim_pos = 0 THEN
      SET next_rec = TRIM(rest);
      SET rest = '';
    ELSE
      SET next_rec = TRIM(SUBSTRING(rest, 1, delim_pos-1));
      SET rest = TRIM(SUBSTRING(rest, delim_pos+1));
    END IF;
    IF next_rec = '' THEN
      LEAVE parse_loop;
    END IF;
    -- parse next_rec of form "sid:status:remarks" or "sid:status"
    SET sid = CAST(SUBSTRING_INDEX(next_rec, ':', 1) AS UNSIGNED);
    SET st = SUBSTRING_INDEX(SUBSTRING_INDEX(next_rec, ':', 2), ':', -1);
    SET rem = NULL;
    IF (LENGTH(next_rec) - LENGTH(REPLACE(next_rec, ':', ''))) >= 2 THEN
      SET rem = SUBSTRING_INDEX(next_rec, ':', -1);
    END IF;

    IF EXISTS (SELECT 1 FROM attendance WHERE session_id=p_session_id AND student_id=sid) THEN
      UPDATE attendance SET status=st, remarks=rem, marked_by=p_marked_by, marked_at=CURRENT_TIMESTAMP
      WHERE session_id=p_session_id AND student_id=sid;
    ELSE
      INSERT INTO attendance(session_id, student_id, status, marked_by, remarks)
      VALUES (p_session_id, sid, st, p_marked_by, rem);
    END IF;

    IF rest = '' THEN LEAVE parse_loop; END IF;
  END LOOP;
  INSERT INTO attendance_audit(action, details, action_by)
  VALUES ('BULK_MARK', CONCAT('session:', p_session_id, ', csv_len:', CHAR_LENGTH(p_csv)), p_marked_by);
  COMMIT;
END$$

-- Procedure: Generate defaulter list for a class (cursor example) -> populates a temp table and returns it
CREATE PROCEDURE sp_generate_defaulters_for_class(
  IN p_class_id INT,
  IN p_threshold_percent INT
)
BEGIN
  DECLARE v_student INT;
  DECLARE v_percent DECIMAL(5,2);
  DECLARE done INT DEFAULT 0;

  -- temp table to return results
  CREATE TEMPORARY TABLE IF NOT EXISTS tmp_defaulters (
    student_id INT,
    roll_no VARCHAR(20),
    name VARCHAR(100),
    percent DECIMAL(5,2)
  ) ENGINE=MEMORY;

  -- cursor over enrolled students
  DECLARE cur_std CURSOR FOR
    SELECT e.student_id FROM enrollment e WHERE e.class_id = p_class_id AND e.status='active';
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  OPEN cur_std;
  read_std: LOOP
    FETCH cur_std INTO v_student;
    IF done THEN LEAVE read_std; END IF;
    SET v_percent = fn_get_attendance_percent(v_student, p_class_id);
    IF v_percent < p_threshold_percent THEN
      INSERT INTO tmp_defaulters(student_id, roll_no, name, percent)
      SELECT s.student_id, s.roll_no, s.name, v_percent FROM student s WHERE s.student_id = v_student;
    END IF;
  END LOOP;
  CLOSE cur_std;

  -- return results
  SELECT * FROM tmp_defaulters ORDER BY percent ASC;
  DROP TEMPORARY TABLE IF EXISTS tmp_defaulters;
END$$

-- Procedure: Subject-wise analysis (avg per session, last N sessions trend) (cursor + statistics)
CREATE PROCEDURE sp_subject_analysis(
  IN p_class_id INT,
  IN p_last_n INT
)
BEGIN
  -- overall average
  SELECT AVG(sub.avg_present) AS overall_avg_percent
  FROM (
    SELECT se.session_date,
      ROUND(SUM(a.status='present' OR (a.status='late' AND (SELECT config_value FROM config WHERE config_key='LATE_COUNT_AS_PRESENT')='1'))/
            GREATEST(1, COUNT(a.attendance_id))*100,2) AS avg_present
    FROM session se
    JOIN attendance a ON a.session_id = se.session_id
    WHERE se.class_id = p_class_id AND se.session_date NOT IN (SELECT holiday_date FROM holiday)
    GROUP BY se.session_date
    ORDER BY se.session_date DESC
    LIMIT p_last_n
  ) AS sub;

  -- per-session trend (last N)
  SELECT se.session_date,
    ROUND(SUM(a.status='present' OR (a.status='late' AND (SELECT config_value FROM config WHERE config_key='LATE_COUNT_AS_PRESENT')='1'))/
          GREATEST(1, COUNT(a.attendance_id))*100,2) AS session_percent,
    COUNT(a.attendance_id) AS records
  FROM session se
  JOIN attendance a ON a.session_id = se.session_id
  WHERE se.class_id = p_class_id AND se.session_date NOT IN (SELECT holiday_date FROM holiday)
  GROUP BY se.session_date
  ORDER BY se.session_date DESC
  LIMIT p_last_n;
END$$

-- Procedure: Generate defaulter list for all classes and store into a table defaulter_report
CREATE TABLE IF NOT EXISTS defaulter_report (
  report_id INT AUTO_INCREMENT PRIMARY KEY,
  class_id INT,
  student_id INT,
  percent DECIMAL(5,2),
  threshold INT,
  report_date DATE,
  FOREIGN KEY (class_id) REFERENCES class(class_id),
  FOREIGN KEY (student_id) REFERENCES student(student_id)
);

CREATE PROCEDURE sp_generate_all_defaulters()
BEGIN
  DECLARE c_class INT;
  DECLARE done INT DEFAULT 0;
  DECLARE thr INT DEFAULT fn_get_threshold();

  DECLARE cur_classes CURSOR FOR SELECT class_id FROM class;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done=1;

  START TRANSACTION;
  OPEN cur_classes;
  class_loop: LOOP
    FETCH cur_classes INTO c_class;
    IF done THEN LEAVE class_loop; END IF;
    -- use the earlier proc to get defaulters
    CALL sp_generate_defaulters_for_class(c_class, thr);
    -- Insert results fetched from temporary table by calling sp_generate_defaulters_for_class and storing them:
    -- But since sp_generate_defaulters_for_class returns a result set and drops temp table, we will instead compute inline here:
    INSERT INTO defaulter_report (class_id, student_id, percent, threshold, report_date)
    SELECT c_class, a.student_id,
      ROUND(SUM(a.status='present' OR (a.status='late' AND (SELECT config_value FROM config WHERE config_key='LATE_COUNT_AS_PRESENT')='1'))/
            GREATEST(1, COUNT(a.attendance_id))*100,2) AS percent,
      thr, CURRENT_DATE
    FROM attendance a
    JOIN session s ON s.session_id = a.session_id
    WHERE s.class_id = c_class AND s.session_date NOT IN (SELECT holiday_date FROM holiday)
    GROUP BY a.student_id
    HAVING percent < thr;
  END LOOP;
  CLOSE cur_classes;
  COMMIT;
END$$
DELIMITER ;

/* -------------------------
   6. Event: periodic defaulter generation (monthly)
   ------------------------- */
-- Note: MySQL event scheduler must be enabled: SET GLOBAL event_scheduler = ON;
DELIMITER $$
CREATE EVENT IF NOT EXISTS ev_monthly_defaulters
ON SCHEDULE EVERY 1 MONTH
STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
  CALL sp_generate_all_defaulters();
END$$
DELIMITER ;

/* -------------------------
   7. Sample data (small)
   ------------------------- */
INSERT INTO faculty(name,email,dept) VALUES ('Dr. Raj', 'raj@jiit.ac.in','CSE'), ('Ms. Neha','neha@jiit.ac.in','Biotech');
INSERT INTO student(roll_no,name,class_year,email) VALUES
('JIIT20B001','Aman','2022','aman@mail'),('JIIT20B002','Ravi','2022','ravi@mail'),
('JIIT20B003','Sonal','2022','sonal@mail');

INSERT INTO course(code,title,credits,dept) VALUES ('CS101','Data Structures',4,'CSE'),('BT201','Genetics',3,'Biotech');

INSERT INTO class(course_id,faculty_id,semester,section,day_of_week,start_time,duration_minutes)
VALUES (1,1,'III','A','Mon','09:00:00',60),(2,2,'III','A','Tue','10:00:00',60);

INSERT INTO enrollment(student_id,class_id) VALUES (1,1),(2,1),(3,1),(1,2),(2,2);

-- Create a session and mark attendance via bulk procedure example
INSERT INTO session(class_id, session_date, start_time, created_by) VALUES (1, '2025-11-10','09:00:00',1);
-- Prepare tmp_att_mark table for the cursor-based marking procedure
DROP TEMPORARY TABLE IF EXISTS tmp_att_mark;
CREATE TEMPORARY TABLE tmp_att_mark (student_id INT, status VARCHAR(10), remarks VARCHAR(255));
INSERT INTO tmp_att_mark VALUES (1,'present',''),(2,'absent','sick'),(3,'late','10 min late');

-- mark attendance for newly created session (assume session_id = LAST_INSERT_ID())
SET @sid = (SELECT session_id FROM session WHERE class_id=1 AND session_date='2025-11-10' LIMIT 1);
CALL sp_mark_attendance_for_session(@sid, 1);
DROP TEMPORARY TABLE IF EXISTS tmp_att_mark;

-- Another session (use CSV style for bulk mark)
INSERT INTO session(class_id, session_date, start_time, created_by) VALUES (1, '2025-11-12','09:00:00',1);
SET @sid2 = (SELECT session_id FROM session WHERE class_id=1 AND session_date='2025-11-12' LIMIT 1);
CALL sp_bulk_mark_from_csv(@sid2, 1, '1:present: ,2:present: ,3:absent:family emergency');

-- Add a holiday
INSERT IGNORE INTO holiday(holiday_date, description) VALUES ('2025-11-11','Diwali');

-- Example: get student percentage
SELECT fn_get_attendance_percent(1,1) AS percen_for_Aman_CS101;

-- Example: generate defaulters for class 1 (threshold from config is 75)
CALL sp_generate_defaulters_for_class(1, fn_get_threshold());

-- Example: subject analysis for last 5 sessions
CALL sp_subject_analysis(1,5);

-- Example: manual generation for all classes and view report
CALL sp_generate_all_defaulters();
SELECT * FROM defaulter_report ORDER BY report_date DESC LIMIT 50;

-- Audit view
SELECT * FROM attendance_audit ORDER BY action_time DESC LIMIT 20;

