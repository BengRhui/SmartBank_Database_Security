# Database Security & SmartBank Security Architecture

A comprehensive SQL Server-based database security project focused on designing and implementing security controls for a banking database system. The project addresses database vulnerabilities through access control, integrity enforcement, data protection, backup and recovery, and auditing to safeguard sensitive information and strengthen database security.

---

## System Architecture

The project applies database security principles to a simulated banking environment consisting of production and analytics databases, with multiple layers of security controls to protect data confidentiality, integrity, and availability.

- **Database Platform:** Microsoft SQL Server
- **Query Language:** Transact-SQL (T-SQL)
- **Databases:** `SmartBankProd`, `SmartBankAnalytics`
- **Access Control:** Authentication, User Management, Role-Based Access Control (RBAC), Row-Level Security (RLS), Views
- **Integrity Controls:** Constraints, Stored Procedures, Triggers
- **Data Protection:** Encryption at Rest, TLS Encryption in Transit, Static and Dynamic Data Masking, Hashing, Anonymisation
- **Backup & Recovery:** Scheduled Backups, Restore and Recovery Procedures
- **Auditing:** Login and Logout, Data Manipulation Language (DML), Data Definition Language (DDL), Permission Changes, Backup and Restore Operations

---

## Core Modules

### Module 1: Database Design & Security Architecture

- **Security Weakness Assessment:** Identifies security weaknesses in the initial database design and proposes an improved security architecture.
- **Data Classification:** Defines the data dictionary and classifies information across production and analytics databases to support appropriate security controls.
- **Database Initialisation:** Establishes the database structures and security-related objects required for subsequent implementations.

### Module 2: Access Control

- **Authentication & User Management:** Configures database authentication and user management to control access to database resources.
- **Role-Based Access Control (RBAC):** Assigns permissions through roles according to users' responsibilities, following the principle of least privilege.
- **Row-Level Security (RLS):** Restricts access to individual records based on defined security policies.
- **Views:** Controls exposure of sensitive data by presenting users with selected columns and records instead of unrestricted access to underlying tables.

### Module 3: Data Integrity Controls

- **Constraints:** Enforces data validation rules and maintains consistency across database records.
- **Stored Procedures:** Implements controlled database operations and centralises business logic to support secure data processing.
- **Triggers:** Automates predefined database actions in response to specified data modification events.

### Module 4: Data Protection Techniques

- **Encryption:** Implements encryption at rest and TLS encryption in transit to protect sensitive information against unauthorised disclosure.
- **Data Masking:** Applies static and dynamic data masking techniques to limit exposure of sensitive information in different usage scenarios.
- **Hashing & Anonymisation:** Explores techniques for protecting sensitive data and reducing the exposure of identifiable information.

### Module 5: Backup & Recovery

- **Backup Strategy:** Defines backup approaches for both `SmartBankProd` and `SmartBankAnalytics` according to their respective data protection requirements.
- **Scheduled Backups:** Configures automated backup operations to support data availability and recovery.
- **Restore & Recovery:** Implements and verifies database restoration procedures to support recovery following data loss or system failure.

### Module 6: Database Auditing & Monitoring

- **Authentication Auditing:** Records login and logout activities to support access monitoring.
- **DML & DDL Auditing:** Tracks data manipulation and database structure changes for accountability and traceability.
- **Permission Change Auditing:** Records changes to database permissions to help identify potentially unauthorised privilege modifications.
- **Backup & Restore Logging:** Monitors backup and restoration activities.
- **Procedure-Level Logging:** Implements logging for selected stored procedure operations.
- **Audit Verification:** Tests and verifies audit configurations to confirm that relevant database activities are recorded.

### Module 7: Security Testing & Verification

- **Security Test Cases:** Executes test cases to verify the implemented security controls and their expected behaviour.
- **Implementation Validation:** Examines access restrictions, data protection mechanisms, integrity enforcement, recovery procedures, and audit records.
- **Security Assessment:** Evaluates the effectiveness of the proposed database security architecture against the identified weaknesses.

---

## Documentation

The full project report that documents the database architecture, security control implementations, configuration procedures, 
test cases, and verification results, can be accessed [here](https://github.com/BengRhui/SmartBank_Database_Security/blob/a150568c604187d787400c6a9526b51612847746/Report/G31%20DBS%20Assignment.pdf).
