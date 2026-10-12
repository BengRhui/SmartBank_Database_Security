
-- Audit for SmartBank --
USE master;
GO

-- Create the server audit --
CREATE SERVER AUDIT SmartBank_ServerAudit TO FILE (
    FILEPATH           = 'C:\SmartBankServer\Audit\',
    MAXSIZE            = 100 MB,
    MAX_ROLLOVER_FILES = 10,
    RESERVE_DISK_SPACE = OFF
) WITH (
    QUEUE_DELAY = 0,
    ON_FAILURE  = CONTINUE
);
GO

-- Enable the server audit --
ALTER SERVER AUDIT SmartBank_ServerAudit WITH (STATE = ON);
GO

-- Create the server audit specification --
CREATE SERVER AUDIT SPECIFICATION SmartBank_ServerAuditSpec
FOR SERVER AUDIT SmartBank_ServerAudit
WITH (STATE = OFF);
GO

-- Create the audit specification for production DB --
USE SmartBankProd;
GO

CREATE DATABASE AUDIT SPECIFICATION SmartBankProd_AuditSpec
FOR SERVER AUDIT SmartBank_ServerAudit
WITH (STATE = OFF);
GO

-- Create the audit specification for analytics DB --
USE SmartBankAnalytics;
GO

CREATE DATABASE AUDIT SPECIFICATION SmartBankAnalytics_AuditSpec
FOR SERVER AUDIT SmartBank_ServerAudit
WITH (STATE = OFF);
GO

-- Login/Logout audit --
USE master;
GO

ALTER SERVER AUDIT SPECIFICATION SmartBank_ServerAuditSpec
    ADD (SUCCESSFUL_LOGIN_GROUP),   -- successful login
    ADD (FAILED_LOGIN_GROUP),       -- rejected login
    ADD (LOGOUT_GROUP);             -- session end
GO

-- Verify that the login/logout audit are enabled --
SELECT  d.audit_action_name, s.name AS SpecificationName, s.is_state_enabled
FROM    sys.server_audit_specifications AS s
JOIN    sys.server_audit_specification_details AS d
        ON d.server_specification_id = s.server_specification_id
WHERE   d.audit_action_name IN ('SUCCESSFUL_LOGIN_GROUP','FAILED_LOGIN_GROUP','LOGOUT_GROUP')
ORDER BY d.audit_action_name;
GO

-- DML audit (production) --
USE SmartBankProd;
GO

ALTER DATABASE AUDIT SPECIFICATION SmartBankProd_AuditSpec

    -- dbo schema --
    ADD (SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo BY public),

    -- Security schema --
    ADD (SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::[Security] BY public);
GO

-- DML audit (analytics) --
USE SmartBankAnalytics;
GO

-- Reporting schema --
ALTER DATABASE AUDIT SPECIFICATION SmartBankAnalytics_AuditSpec
    ADD (SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::Reporting BY public);
GO

-- Temporal table (production) --
USE SmartBankProd;
GO

-- Staff table --
ALTER TABLE dbo.Staff ADD
    SysStartTime DATETIME2 
        GENERATED ALWAYS AS ROW START 
        NOT NULL 
        CONSTRAINT DF_Staff_SysStart DEFAULT SYSUTCDATETIME(),
    SysEndTime DATETIME2 
        GENERATED ALWAYS AS ROW END   
        NOT NULL 
        CONSTRAINT DF_Staff_SysEnd DEFAULT '9999-12-31 23:59:59.9999999',
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime);
GO

ALTER TABLE dbo.Staff 
    SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.StaffHistory));
GO

-- Customer table --
ALTER TABLE dbo.Customer ADD
    SysStartTime DATETIME2 
        GENERATED ALWAYS AS ROW START 
        NOT NULL
        CONSTRAINT DF_Customer_SysStart DEFAULT SYSUTCDATETIME(),
    SysEndTime DATETIME2 
        GENERATED ALWAYS AS ROW END
        NOT NULL
        CONSTRAINT DF_Customer_SysEnd DEFAULT '9999-12-31 23:59:59.9999999',
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime);
GO

ALTER TABLE dbo.Customer 
    SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.CustomerHistory));
GO

-- Account table --
ALTER TABLE dbo.Account ADD
    SysStartTime DATETIME2
        GENERATED ALWAYS AS ROW START
        NOT NULL
        CONSTRAINT DF_Account_SysStart DEFAULT SYSUTCDATETIME(),
    SysEndTime DATETIME2 
        GENERATED ALWAYS AS ROW END
        NOT NULL
        CONSTRAINT DF_Account_SysEnd DEFAULT '9999-12-31 23:59:59.9999999',
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime);
GO

ALTER TABLE dbo.Account 
    SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.AccountHistory));
GO

-- Security.UserMapping table --
ALTER TABLE [Security].UserMapping ADD
    SysStartTime DATETIME2 
        GENERATED ALWAYS AS ROW START 
        NOT NULL
        CONSTRAINT DF_UserMapping_SysStart DEFAULT SYSUTCDATETIME(),
    SysEndTime DATETIME2 
        GENERATED ALWAYS AS ROW END
        NOT NULL
        CONSTRAINT DF_UserMapping_SysEnd DEFAULT '9999-12-31 23:59:59.9999999',
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime);
GO

ALTER TABLE [Security].UserMapping
    SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [Security].UserMappingHistory));
GO

-- Security.RejectedAttemptLog --
ALTER TABLE [Security].RejectedAttemptLog ADD
    SysStartTime DATETIME2 
        GENERATED ALWAYS AS ROW START
        NOT NULL
        CONSTRAINT DF_RejectedAttemptLog_SysStart DEFAULT SYSUTCDATETIME(),
    SysEndTime DATETIME2 
        GENERATED ALWAYS AS ROW END
        NOT NULL
        CONSTRAINT DF_RejectedAttemptLog_SysEnd DEFAULT '9999-12-31 23:59:59.9999999',
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime);
GO

ALTER TABLE [Security].RejectedAttemptLog 
    SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [Security].RejectedAttemptLogHistory));
GO

-- Deny direct access to temporal tables for all users --
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.StaffHistory
    TO role_DBA, role_Manager, role_Officer, role_Customer, role_ETL_Reader;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.CustomerHistory
    TO role_DBA, role_Manager, role_Officer, role_Customer, role_ETL_Reader;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.AccountHistory
    TO role_DBA, role_Manager, role_Officer, role_Customer, role_ETL_Reader;
DENY SELECT, INSERT, UPDATE, DELETE ON [Security].UserMappingHistory
    TO role_DBA, role_Manager, role_Officer, role_Customer, role_ETL_Reader;
DENY SELECT, INSERT, UPDATE, DELETE ON [Security].RejectedAttemptLogHistory
    TO role_DBA, role_Manager, role_Officer, role_Customer, role_ETL_Reader;
GO

-- Verify that DML audit is configured for production and analytics DB --
USE SmartBankProd;
GO
SELECT  s.name AS SpecificationName, d.audit_action_name, d.class_desc,
        CASE d.class_desc
            WHEN 'OBJECT_OR_COLUMN' THEN OBJECT_NAME(d.major_id)
            WHEN 'SCHEMA'           THEN SCHEMA_NAME(d.major_id)
        END AS AuditedObject,
        d.audited_principal_id
FROM    sys.database_audit_specifications AS s
JOIN    sys.database_audit_specification_details AS d
        ON d.database_specification_id = s.database_specification_id
WHERE   d.class_desc IN ('OBJECT_OR_COLUMN','SCHEMA')
ORDER BY AuditedObject, audit_action_name;
GO

USE SmartBankAnalytics;
GO
SELECT  s.name AS SpecificationName, d.audit_action_name, d.class_desc,
        CASE d.class_desc
            WHEN 'OBJECT_OR_COLUMN' THEN OBJECT_NAME(d.major_id)
            WHEN 'SCHEMA'           THEN SCHEMA_NAME(d.major_id)
        END AS AuditedObject,
        d.audited_principal_id
FROM    sys.database_audit_specifications AS s
JOIN    sys.database_audit_specification_details AS d
        ON d.database_specification_id = s.database_specification_id
WHERE   d.class_desc IN ('OBJECT_OR_COLUMN','SCHEMA')
ORDER BY AuditedObject, audit_action_name;
GO

-- Verify that temporal tables are setup correctly --
USE SmartBankProd;
GO

SELECT  sc.name AS SchemaName, t.name AS TableName, t.temporal_type_desc,
        h.name  AS HistoryTableName
FROM    sys.tables AS t
JOIN    sys.schemas AS sc ON sc.schema_id = t.schema_id
LEFT JOIN sys.tables AS h ON h.object_id = t.history_table_id
WHERE   (sc.name = 'dbo' AND t.name IN ('Staff','Customer','Account'))
   OR   (sc.name = 'Security' AND t.name IN ('UserMapping','RejectedAttemptLog'))
ORDER BY sc.name, t.name;

-- Verify that no one has direct access to the history table --
USE SmartBankProd;
GO

SELECT  OBJECT_SCHEMA_NAME(p.major_id) AS SchemaName,
        OBJECT_NAME(p.major_id)        AS HistoryTableName,
        dp.name                        AS GranteeRole,
        p.permission_name, p.state_desc
FROM    sys.database_permissions AS p
JOIN    sys.database_principals  AS dp ON dp.principal_id = p.grantee_principal_id
WHERE   p.major_id IN (
            OBJECT_ID('dbo.StaffHistory'), OBJECT_ID('dbo.CustomerHistory'),
            OBJECT_ID('dbo.AccountHistory'),
            OBJECT_ID('Security.UserMappingHistory'),
            OBJECT_ID('Security.RejectedAttemptLogHistory'));
GO

-- DDL audit --
USE master;
GO

ALTER SERVER AUDIT SPECIFICATION SmartBank_ServerAuditSpec
    ADD (DATABASE_CHANGE_GROUP);        -- Alter database
GO

USE SmartBankProd;
GO

ALTER DATABASE AUDIT SPECIFICATION SmartBankProd_AuditSpec
    ADD (SCHEMA_OBJECT_CHANGE_GROUP),    -- Tables and views
    ADD (DATABASE_OBJECT_CHANGE_GROUP);  -- Stored procedure, functions, policies
GO

USE SmartBankAnalytics;
GO

ALTER DATABASE AUDIT SPECIFICATION SmartBankAnalytics_AuditSpec
    ADD (SCHEMA_OBJECT_CHANGE_GROUP),
    ADD (DATABASE_OBJECT_CHANGE_GROUP);
GO

-- Verify for server audit spec --
SELECT  d.audit_action_name, s.name AS SpecificationName, s.is_state_enabled
FROM    sys.server_audit_specifications AS s
JOIN    sys.server_audit_specification_details AS d
        ON d.server_specification_id = s.server_specification_id
WHERE   d.audit_action_name IN ('DATABASE_CHANGE_GROUP')
ORDER BY d.audit_action_name;
GO

-- Verify for database audit spec (production & analytics) --
SELECT  'SmartBankProd' AS DatabaseName, s.name AS SpecificationName,
        d.audit_action_name, d.class_desc, d.audited_principal_id
FROM    SmartBankProd.sys.database_audit_specifications AS s
JOIN    SmartBankProd.sys.database_audit_specification_details AS d
        ON d.database_specification_id = s.database_specification_id
WHERE   d.audit_action_name IN ('SCHEMA_OBJECT_CHANGE_GROUP','DATABASE_OBJECT_CHANGE_GROUP')
UNION ALL
SELECT  'SmartBankAnalytics', s.name,
        d.audit_action_name, d.class_desc, d.audited_principal_id
FROM    SmartBankAnalytics.sys.database_audit_specifications AS s
JOIN    SmartBankAnalytics.sys.database_audit_specification_details AS d
        ON d.database_specification_id = s.database_specification_id
WHERE   d.audit_action_name IN ('SCHEMA_OBJECT_CHANGE_GROUP','DATABASE_OBJECT_CHANGE_GROUP')
ORDER BY DatabaseName, audit_action_name;
GO

-- Permission change audit --
USE master;
GO

ALTER SERVER AUDIT SPECIFICATION SmartBank_ServerAuditSpec
    ADD (SERVER_PRINCIPAL_CHANGE_GROUP),        -- login created / altered / dropped
    ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),      -- someone made sysadmin
    ADD (SERVER_PERMISSION_CHANGE_GROUP),       -- e.g. GRANT CONTROL SERVER
    ADD (LOGIN_CHANGE_PASSWORD_GROUP),          -- password reset, self or admin
    ADD (SERVER_PRINCIPAL_IMPERSONATION_GROUP), -- EXECUTE AS LOGIN
    ADD (DATABASE_OWNERSHIP_CHANGE_GROUP);      -- ALTER AUTHORIZATION ON DATABASE
GO

USE SmartBankProd;
GO

ALTER DATABASE AUDIT SPECIFICATION SmartBankProd_AuditSpec
    ADD (DATABASE_PERMISSION_CHANGE_GROUP),
    ADD (SCHEMA_OBJECT_PERMISSION_CHANGE_GROUP),
    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
    ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
    ADD (DATABASE_PRINCIPAL_IMPERSONATION_GROUP),  -- EXECUTE AS USER
    ADD (SCHEMA_OBJECT_OWNERSHIP_CHANGE_GROUP);    -- ALTER AUTHORIZATION on an object
GO

USE SmartBankAnalytics;
GO

ALTER DATABASE AUDIT SPECIFICATION SmartBankAnalytics_AuditSpec
    ADD (DATABASE_PERMISSION_CHANGE_GROUP),
    ADD (SCHEMA_OBJECT_PERMISSION_CHANGE_GROUP),
    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
    ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
    ADD (DATABASE_PRINCIPAL_IMPERSONATION_GROUP),  -- EXECUTE AS USER
    ADD (SCHEMA_OBJECT_OWNERSHIP_CHANGE_GROUP);    -- ALTER AUTHORIZATION on an object
GO

-- Verify permission change for server audit spec --
SELECT  d.audit_action_name, s.name AS SpecificationName, s.is_state_enabled
FROM    sys.server_audit_specifications AS s
JOIN    sys.server_audit_specification_details AS d
        ON d.server_specification_id = s.server_specification_id
WHERE   d.audit_action_name IN ('SERVER_PRINCIPAL_CHANGE_GROUP',
                                'SERVER_ROLE_MEMBER_CHANGE_GROUP',
                                'SERVER_PERMISSION_CHANGE_GROUP',
                                'LOGIN_CHANGE_PASSWORD_GROUP',
                                'SERVER_PRINCIPAL_IMPERSONATION_GROUP',
                                'DATABASE_OWNERSHIP_CHANGE_GROUP')
ORDER BY d.audit_action_name;
GO

-- Verify permission change for database audit spec --
SELECT  'SmartBankProd' AS DatabaseName, s.name AS SpecificationName,
        d.audit_action_name, d.class_desc, d.audited_principal_id
FROM    SmartBankProd.sys.database_audit_specifications AS s
JOIN    SmartBankProd.sys.database_audit_specification_details AS d
        ON d.database_specification_id = s.database_specification_id
WHERE   d.audit_action_name LIKE '%PERMISSION_CHANGE_GROUP'
     OR d.audit_action_name LIKE '%PRINCIPAL_CHANGE_GROUP'
     OR d.audit_action_name LIKE '%ROLE_MEMBER_CHANGE_GROUP'
     OR d.audit_action_name LIKE '%IMPERSONATION_GROUP'
     OR d.audit_action_name LIKE '%OWNERSHIP_CHANGE_GROUP'
UNION ALL
SELECT  'SmartBankAnalytics', s.name,
        d.audit_action_name, d.class_desc, d.audited_principal_id
FROM    SmartBankAnalytics.sys.database_audit_specifications AS s
JOIN    SmartBankAnalytics.sys.database_audit_specification_details AS d
        ON d.database_specification_id = s.database_specification_id
WHERE   d.audit_action_name LIKE '%PERMISSION_CHANGE_GROUP'
     OR d.audit_action_name LIKE '%PRINCIPAL_CHANGE_GROUP'
     OR d.audit_action_name LIKE '%ROLE_MEMBER_CHANGE_GROUP'
     OR d.audit_action_name LIKE '%IMPERSONATION_GROUP'
     OR d.audit_action_name LIKE '%OWNERSHIP_CHANGE_GROUP'
ORDER BY DatabaseName, audit_action_name;
GO

-- Additional: Audit, backup and restore --
USE master;
GO

ALTER SERVER AUDIT SPECIFICATION SmartBank_ServerAuditSpec
    ADD (AUDIT_CHANGE_GROUP),          -- audit the audit itself
    ADD (BACKUP_RESTORE_GROUP),        -- data leaving the server
    ADD (SERVER_STATE_CHANGE_GROUP),   -- service stopped = audit silenced
    ADD (DBCC_GROUP);                  -- DBCC can read raw pages
GO

-- Verify that audits related to audit, backup and restore are configured --
SELECT  d.audit_action_name, s.name AS SpecificationName, s.is_state_enabled
FROM    sys.server_audit_specifications AS s
JOIN    sys.server_audit_specification_details AS d
        ON d.server_specification_id = s.server_specification_id
WHERE   d.audit_action_name IN ('AUDIT_CHANGE_GROUP',
                                'BACKUP_RESTORE_GROUP',
                                'SERVER_STATE_CHANGE_GROUP',
                                'DBCC_GROUP')
ORDER BY d.audit_action_name;
GO

-- Enable all audit specifications --
USE master;
GO
ALTER SERVER AUDIT SPECIFICATION SmartBank_ServerAuditSpec WITH (STATE = ON);
GO

USE SmartBankProd;
GO
ALTER DATABASE AUDIT SPECIFICATION SmartBankProd_AuditSpec WITH (STATE = ON);
GO

USE SmartBankAnalytics;
GO
ALTER DATABASE AUDIT SPECIFICATION SmartBankAnalytics_AuditSpec WITH (STATE = ON);
GO

-- Confirm that all audit specifications are activated --
SELECT 'SERVER' AS Scope, name, is_state_enabled
FROM   master.sys.server_audit_specifications
UNION ALL
SELECT 'SmartBankProd', name, is_state_enabled
FROM   SmartBankProd.sys.database_audit_specifications
UNION ALL
SELECT 'SmartBankAnalytics', name, is_state_enabled
FROM   SmartBankAnalytics.sys.database_audit_specifications;
GO

/* ========== Verification: Prove that audit works ========== */
-- Login and logout audit --
USE master;
GO

-- Steps to perform (this has to be performed when users login) --
-- 1. smartbank_admin key in the wrong password
-- 2. smartbank_admin key in the correct password
-- 3. smartbank_admin ends his connection
-- 4. Now run the script for login/logout audit
SELECT  event_time, action_id, succeeded, server_principal_name, statement
FROM    sys.fn_get_audit_file('C:\SmartBankServer\Audit\*.sqlaudit', DEFAULT, DEFAULT)
WHERE   action_id IN ('LGIS','LGIF','LGO')
ORDER BY event_time DESC;
GO

-- DML audit --
USE SmartBankProd;
GO

-- Case 1: SELECT a permitted view --
EXECUTE AS USER = 'ofc_lim';
SELECT * FROM dbo.vw_StaffDirectory;
GO
REVERT;
GO

-- Case 2: INSERT on Account table --
EXECUTE AS USER = 'ofc_lim';
INSERT INTO dbo.Account (AccountID, CustomerID, AccountType, Balance)
VALUES ('ACC9999999', 'C00001', 'Savings', 0);
GO
REVERT;
GO

-- Case 3: UPDATE on Customer table --
EXECUTE AS USER = 'ofc_lim';
UPDATE dbo.Customer SET Address = '123 Test Street' WHERE CustomerID = 'C00001';
GO
REVERT;
GO

-- Case 4: EXEC a stored procedure --
EXECUTE AS USER = 'ofc_lim';
EXEC dbo.usp_UpdateOwnStaffRecord @Phone = '012-3450099';
GO
REVERT;
GO

-- View audit logs --
SELECT  event_time, action_id, succeeded, server_principal_name,
        database_principal_name, object_name, statement
FROM    sys.fn_get_audit_file('C:\SmartBankServer\Audit\*.sqlaudit', DEFAULT, DEFAULT)
WHERE   action_id IN ('IN','UP','DL','SL')       -- insert, update, delete, select
        AND server_principal_name = 'ofc_lim'  
ORDER BY event_time DESC;
GO

-- Verify: View versioned table --
SELECT  StaffID, StaffName, Phone, SysStartTime, SysEndTime
FROM    dbo.Staff
FOR SYSTEM_TIME ALL
WHERE   StaffID = 'S00004'
ORDER BY SysStartTime DESC;
GO

-- DDL audit --
USE SmartBankProd;
GO

-- Create a table --
CREATE TABLE dbo.AuditProbe_TempTable (ProbeID INT);
GO

-- Drop a table --
DROP TABLE IF EXISTS dbo.AuditProbe_TempTable;
GO

-- DDL performed by customer --
EXECUTE AS USER = 'cust_tan';
CREATE TABLE dbo.AuditProbe_Unauthorised (ProbeID INT);
GO
REVERT;
GO

--  Set database recovery model to full (by default it's full as well) --
USE master;
GO
ALTER DATABASE SmartBankProd SET RECOVERY FULL;
GO

-- Verify that DDL is captured --
SELECT  a.event_time, a.action_id, a.succeeded, a.server_principal_name,
        a.database_principal_name, a.object_name, a.statement
FROM    sys.fn_get_audit_file('C:\SmartBankServer\Audit\*.sqlaudit', DEFAULT, DEFAULT) AS a
CROSS APPLY (VALUES (LTRIM(REPLACE(REPLACE(a.statement, CHAR(13), ' '), CHAR(10), ' ')))) AS n(NormalisedStatement)
WHERE   a.action_id IN ('CR','AL','DR')        -- create, alter, drop
   OR   n.NormalisedStatement LIKE 'CREATE %'
   OR   n.NormalisedStatement LIKE 'ALTER %'
   OR   n.NormalisedStatement LIKE 'DROP %'
ORDER BY a.event_time DESC;
GO

-- Permission change audit --
USE SmartBankProd;
GO

-- Grant existing permission --
GRANT SELECT ON dbo.vw_StaffDirectory TO role_Customer;
GO

-- Attempt to revoke existing permission as customer --
EXECUTE AS USER = 'cust_tan';
REVOKE SELECT ON dbo.vw_StaffDirectory TO role_Customer;
GO
REVERT;
GO

-- Verify: Permission changes are recorded in audit --
SELECT  a.event_time, a.action_id, a.succeeded, a.server_principal_name,
        a.database_principal_name, a.object_name, a.statement
FROM    sys.fn_get_audit_file('C:\SmartBankServer\Audit\*.sqlaudit', DEFAULT, DEFAULT) AS a
CROSS APPLY (VALUES (LTRIM(REPLACE(REPLACE(a.statement, CHAR(13), ' '), CHAR(10), ' ')))) AS n(NormalisedStatement)
WHERE   a.action_id IN ('G','D','R','GWG','RWG','PWCG','IMP','TO')
   OR   n.NormalisedStatement LIKE 'GRANT %'
   OR   n.NormalisedStatement LIKE 'DENY %'
   OR   n.NormalisedStatement LIKE 'REVOKE %'
   OR   n.NormalisedStatement LIKE 'ALTER ROLE%'
   OR   n.NormalisedStatement LIKE 'ALTER LOGIN%'
   OR   n.NormalisedStatement LIKE 'EXECUTE AS%'
   OR   n.NormalisedStatement LIKE 'ALTER AUTHORIZATION%'
ORDER BY a.event_time DESC;
GO

-- Audit, backup and restore logging --
USE master;
GO

-- Perform full backup --
BACKUP DATABASE SmartBankProd
    TO DISK = 'C:\SmartBankServer\Backup\Production\AuditProbe_CopyOnly.bak'
    WITH COPY_ONLY, INIT, COMPRESSION,
         NAME = 'SmartBankProd audit probe (copy-only)';
GO

-- Disable and re-enable audit logs --
ALTER SERVER AUDIT SmartBank_ServerAudit WITH (STATE = OFF);
GO
ALTER SERVER AUDIT SmartBank_ServerAudit WITH (STATE = ON);
GO

-- Verify that logging performs as intended --
SELECT  a.event_time, a.action_id, a.succeeded, a.server_principal_name,
        a.database_name, a.object_name, a.statement
FROM    sys.fn_get_audit_file('C:\SmartBankServer\Audit\*.sqlaudit', DEFAULT, DEFAULT) AS a
CROSS APPLY (VALUES (LTRIM(REPLACE(REPLACE(a.statement, CHAR(13), ' '), CHAR(10), ' ')))) AS n(NormalisedStatement)
WHERE   a.action_id IN ('SVCN','SVPD','SVSD','SVSR','DBCC')  -- service state changes, DBCC
   OR   n.NormalisedStatement LIKE 'ALTER SERVER AUDIT%'
   OR   n.NormalisedStatement LIKE 'CREATE SERVER AUDIT%'
   OR   n.NormalisedStatement LIKE 'DROP SERVER AUDIT%'
   OR   n.NormalisedStatement LIKE 'ALTER DATABASE%'
   OR   n.NormalisedStatement LIKE 'BACKUP %'
   OR   n.NormalisedStatement LIKE 'RESTORE %'
   OR   n.NormalisedStatement LIKE 'DBCC %'
ORDER BY a.event_time DESC;
GO

-- Procedure-level logging --
USE SmartBankProd;
GO

-- Create account with negative balance --
EXECUTE AS USER = 'ofc_lim';
EXEC dbo.usp_CreateCustomerAccount @AccountID = 'ACC9999998',
                                   @CustomerID = 'C00001',
                                   @AccountType = 'Savings',
                                   @OpeningBalance = -500.00;
GO
REVERT;
GO

-- Verify that procedure-level logging takes place --
SELECT TOP (100) * FROM Security.RejectedAttemptLog 
ORDER BY AttemptID DESC;
GO


/* -- Run the following code if anything goes wrong --

-- Remove temporal tables --
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Staff' AND temporal_type = 2)
BEGIN
    ALTER TABLE dbo.Staff SET (SYSTEM_VERSIONING = OFF);
    ALTER TABLE dbo.Staff DROP PERIOD FOR SYSTEM_TIME;
    ALTER TABLE dbo.Staff DROP CONSTRAINT DF_Staff_SysStart, DF_Staff_SysEnd, COLUMN SysStartTime, SysEndTime;
    DROP TABLE IF EXISTS dbo.StaffHistory;
END
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Customer' AND temporal_type = 2)
BEGIN
    ALTER TABLE dbo.Customer SET (SYSTEM_VERSIONING = OFF);
    ALTER TABLE dbo.Customer DROP PERIOD FOR SYSTEM_TIME;
    ALTER TABLE dbo.Customer DROP CONSTRAINT DF_Customer_SysStart, DF_Customer_SysEnd, COLUMN SysStartTime, SysEndTime;
    DROP TABLE IF EXISTS dbo.CustomerHistory;
END
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Account' AND temporal_type = 2)
BEGIN
    ALTER TABLE dbo.Account SET (SYSTEM_VERSIONING = OFF);
    ALTER TABLE dbo.Account DROP PERIOD FOR SYSTEM_TIME;
    ALTER TABLE dbo.Account DROP CONSTRAINT DF_Account_SysStart, DF_Account_SysEnd, COLUMN SysStartTime, SysEndTime;
    DROP TABLE IF EXISTS dbo.AccountHistory;
END
IF EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas sc ON sc.schema_id = t.schema_id
           WHERE t.name = 'UserMapping' AND sc.name = 'Security' AND t.temporal_type = 2)
BEGIN
    ALTER TABLE [Security].UserMapping SET (SYSTEM_VERSIONING = OFF);
    ALTER TABLE [Security].UserMapping DROP PERIOD FOR SYSTEM_TIME;
    ALTER TABLE [Security].UserMapping DROP CONSTRAINT DF_UserMapping_SysStart, DF_UserMapping_SysEnd, COLUMN SysStartTime, SysEndTime;
    DROP TABLE IF EXISTS [Security].UserMappingHistory;
END
IF EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas sc ON sc.schema_id = t.schema_id
           WHERE t.name = 'RejectedAttemptLog' AND sc.name = 'Security' AND t.temporal_type = 2)
BEGIN
    ALTER TABLE [Security].RejectedAttemptLog SET (SYSTEM_VERSIONING = OFF);
    ALTER TABLE [Security].RejectedAttemptLog DROP PERIOD FOR SYSTEM_TIME;
    ALTER TABLE [Security].RejectedAttemptLog DROP CONSTRAINT DF_RejectedAttemptLog_SysStart, DF_RejectedAttemptLog_SysEnd, COLUMN SysStartTime, SysEndTime;
    DROP TABLE IF EXISTS [Security].RejectedAttemptLogHistory;
END
GO

-- Remove audit specifications and server audit --
USE SmartBankProd;
GO
IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = 'SmartBankProd_AuditSpec')
BEGIN ALTER DATABASE AUDIT SPECIFICATION SmartBankProd_AuditSpec WITH (STATE = OFF);
      DROP  DATABASE AUDIT SPECIFICATION SmartBankProd_AuditSpec;
END
GO
USE SmartBankAnalytics;
GO
IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = 'SmartBankAnalytics_AuditSpec')
BEGIN ALTER DATABASE AUDIT SPECIFICATION SmartBankAnalytics_AuditSpec WITH (STATE = OFF);
      DROP  DATABASE AUDIT SPECIFICATION SmartBankAnalytics_AuditSpec;
END
GO
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = 'SmartBank_ServerAuditSpec')
BEGIN ALTER SERVER AUDIT SPECIFICATION SmartBank_ServerAuditSpec WITH (STATE = OFF);
      DROP  SERVER AUDIT SPECIFICATION SmartBank_ServerAuditSpec;
END
GO
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'SmartBank_ServerAudit')
BEGIN ALTER SERVER AUDIT SmartBank_ServerAudit WITH (STATE = OFF);
      DROP  SERVER AUDIT SmartBank_ServerAudit;
END
GO
*/
