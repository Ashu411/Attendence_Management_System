Attendance Management System (MySQL)
Overview

This project is a database-driven Attendance Management System implemented using MySQL. It is designed to manage student attendance efficiently in an academic environment. The system supports storing, updating, and analyzing attendance data while maintaining data integrity.

Features
Core Functionality
Management of students, faculty, and courses
Class scheduling and enrollment system
Session-based attendance recording
Data Handling
Prevention of duplicate attendance entries
Audit logging of all attendance operations
Configurable attendance threshold
Reporting and Analysis
Student-wise attendance summary
Subject-wise attendance analysis
Identification of defaulters based on attendance percentage
Automation
Use of triggers for validation and logging
Stored procedures for attendance marking and reporting
Event scheduler for periodic defaulter report generation
Database Structure

The system consists of the following tables:

student: Stores student information
faculty: Stores faculty details
course: Contains course-related data
class: Represents scheduled classes
enrollment: Maps students to classes
session: Represents individual lecture sessions
attendance: Stores attendance records
holiday: Stores holiday dates
config: Stores system configuration values
attendance_audit: Maintains logs of operations

Full schema is available in the SQL file:


System Workflow
Faculty creates a class for a course
Students are enrolled in the class
Sessions are created for each lecture
Attendance is recorded for each session
The system calculates attendance percentages and generates reports
Key Procedures
sp_create_session: Creates a session for a class
sp_mark_attendance_for_session: Marks attendance using a cursor-based approach
sp_bulk_mark_from_csv: Allows bulk attendance marking using input strings
sp_generate_defaulters_for_class: Identifies students below the attendance threshold
sp_subject_analysis: Provides attendance trends and analysis
Views
v_student_att_summary: Provides per-student attendance statistics
v_subject_att_summary: Provides subject-level attendance insights
Data Integrity

The system ensures data reliability through:

Triggers to prevent duplicate records
Foreign key constraints
Audit logs for tracking changes
Sample Queries
-- Calculate attendance percentage
SELECT fn_get_attendance_percent(1,1);

-- Generate defaulter list
CALL sp_generate_defaulters_for_class(1, 75);

-- Perform subject analysis
CALL sp_subject_analysis(1,5);
Setup Instructions
Install MySQL
Open MySQL Workbench or command line interface
Execute the provided SQL script
The database named "project" will be created automatically
Requirements
MySQL 5.7 or higher (MySQL 8.0 recommended)

To enable scheduled events:

SET GLOBAL event_scheduler = ON;
Use Cases
Academic institutions for attendance tracking
Database management system projects
Backend systems for ERP solutions
Future Scope
Integration with a web or mobile interface
Role-based login system
Dashboard for real-time analytics


Author
Ashutosh Kumar
B.Tech, JIIT Noida
