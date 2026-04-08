Attendance Management System (MySQL)
Overview

This project is a MySQL-based Attendance Management System designed to handle student attendance efficiently in an academic environment. It supports attendance tracking, analysis, and reporting with proper data integrity.

Features
Student, faculty, and course management
Class scheduling and enrollment
Session-based attendance recording
Attendance percentage calculation
Defaulter identification
Audit logging and duplicate prevention
Automated reports using procedures and events
Database Structure

Main tables include:
student, faculty, course, class, enrollment, session, attendance, holiday, config, attendance_audit

Full schema:


Key Functions
Attendance marking (single and bulk)
Attendance percentage calculation
Defaulter list generation
Subject-wise analysis
Setup
Install MySQL
Run the SQL script
Database project will be created

Enable events if needed:

SET GLOBAL event_scheduler = ON;


Author
Ashutosh Kumar
B.Tech, JIIT Noida
