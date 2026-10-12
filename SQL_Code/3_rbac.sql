
-- Create roles for production DB --
USE SmartBankProd;
GO

CREATE ROLE role_DBA;
CREATE ROLE role_Manager;
CREATE ROLE role_Officer;
CREATE ROLE role_Customer;
CREATE ROLE role_ETL_Reader;
GO

-- Add users to respective roles --
ALTER ROLE role_DBA         ADD MEMBER [dba_ahmad];
ALTER ROLE role_Manager     ADD MEMBER [mgr_aisyah];
ALTER ROLE role_Manager     ADD MEMBER [mgr_ravi];
ALTER ROLE role_Officer     ADD MEMBER [ofc_lim];
ALTER ROLE role_Officer     ADD MEMBER [ofc_nurul];
ALTER ROLE role_Customer    ADD MEMBER [cust_tan];
ALTER ROLE role_Customer    ADD MEMBER [cust_siti];
ALTER ROLE role_Customer    ADD MEMBER [cust_kumar];
ALTER ROLE role_Customer    ADD MEMBER [cust_wong];
ALTER ROLE role_ETL_Reader  ADD MEMBER [svc_ETL];
GO

-- Create roles for analytics DB --
USE SmartBankAnalytics;
GO

CREATE ROLE role_ETL_Service;
CREATE ROLE role_Analyst_ReadOnly;
GO

-- Add users to respective roles --
ALTER ROLE role_ETL_Service      ADD MEMBER [svc_ETL];
ALTER ROLE role_Analyst_ReadOnly ADD MEMBER [analyst_lee];
GO

-- Configure user access for production DB --
USE SmartBankProd;
GO

-- Prevent direct access to tables in production --
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Staff             TO role_DBA, role_Manager, role_Officer, role_Customer;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Customer          TO role_DBA, role_Manager, role_Officer, role_Customer;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Account           TO role_DBA, role_Manager, role_Officer, role_Customer;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.TransactionRecord TO role_DBA, role_Manager, role_Officer, role_Customer;
GO

-- DBA can perform DDL tasks but not config user account --
GRANT CREATE TABLE          TO role_DBA;
GRANT CREATE VIEW           TO role_DBA;
GRANT CREATE PROCEDURE      TO role_DBA;
GRANT CREATE FUNCTION       TO role_DBA;
GRANT ALTER ON SCHEMA::dbo  TO role_DBA;
DENY ALTER ANY ROLE         TO role_DBA;
DENY ALTER ANY USER         TO role_DBA;
GO

-- Only read access for Security.UserMapping table (for RLS) --
GRANT SELECT ON [Security].UserMapping TO role_DBA, role_Manager, role_Officer, role_Customer;
DENY SELECT, INSERT, UPDATE, DELETE ON [Security].RejectedAttemptLog
    TO role_DBA, role_Manager, role_Officer, role_Customer, role_ETL_Reader;
GO

-- Service account can only read from production DB --
GRANT SELECT ON dbo.Customer                         TO role_ETL_Reader;
GRANT SELECT ON dbo.Account                          TO role_ETL_Reader;
GRANT SELECT ON dbo.TransactionRecord                TO role_ETL_Reader;
DENY INSERT, UPDATE, DELETE ON dbo.Customer          TO role_ETL_Reader;
DENY INSERT, UPDATE, DELETE ON dbo.Account           TO role_ETL_Reader;
DENY INSERT, UPDATE, DELETE ON dbo.TransactionRecord TO role_ETL_Reader;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Staff     TO role_ETL_Reader;
GO

-- Configure user access for analytics DB --
USE SmartBankAnalytics;
GO

-- Only ETL service can write to Reporting --
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Reporting TO role_ETL_Service;

-- Analysts have no direct access to raw tables --  
DENY INSERT, UPDATE, DELETE ON SCHEMA::Reporting TO role_Analyst_ReadOnly;
DENY SELECT ON Reporting.DimCustomer             TO role_Analyst_ReadOnly;
DENY SELECT ON Reporting.FactAccount             TO role_Analyst_ReadOnly;
DENY SELECT ON Reporting.FactTransaction         TO role_Analyst_ReadOnly;
DENY SELECT ON Reporting.ETLRunLog               TO role_Analyst_ReadOnly;
GO

-- Verification after done --
USE SmartBankProd;
GO

-- Verify the roles and members involved in the production DB --
SELECT  r.name  AS RoleName,
        m.name  AS MemberName
FROM    sys.database_role_members rm
JOIN    sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN    sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE   r.name LIKE 'role[_]%'
ORDER BY r.name, m.name;
GO

-- Verify if objects in production DB are granted to correct role and access --
SELECT  p.class_desc,
        CASE p.class_desc
            WHEN 'OBJECT_OR_COLUMN' THEN OBJECT_NAME(p.major_id)
            WHEN 'SCHEMA'           THEN SCHEMA_NAME(p.major_id)
            WHEN 'DATABASE'         THEN DB_NAME()
        END                         AS ObjectName,
        dp.name                     AS RoleName,
        p.permission_name,
        p.state_desc                AS GrantOrDeny
FROM    sys.database_permissions p
JOIN    sys.database_principals dp ON dp.principal_id = p.grantee_principal_id
WHERE   dp.name LIKE 'role[_]%'
ORDER BY dp.name, ObjectName, p.permission_name;
GO

-- Perform similar checking for analytics DB --
USE SmartBankAnalytics;
GO

-- Check the users assigned under each role in analytics DB --
SELECT  r.name  AS RoleName,
        m.name  AS MemberName
FROM    sys.database_role_members rm
JOIN    sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN    sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE   r.name LIKE 'role[_]%'
ORDER BY r.name, m.name;
GO

-- Verify if the objects in analytics DB are allocated to the correct role and access --
SELECT  p.class_desc,
        CASE p.class_desc
            WHEN 'OBJECT_OR_COLUMN' THEN OBJECT_NAME(p.major_id)
            WHEN 'SCHEMA'           THEN SCHEMA_NAME(p.major_id)
            WHEN 'DATABASE'         THEN DB_NAME()
        END                         AS ObjectName,
        dp.name                     AS RoleName,
        p.permission_name,
        p.state_desc                AS GrantOrDeny
FROM    sys.database_permissions p
JOIN    sys.database_principals dp ON dp.principal_id = p.grantee_principal_id
WHERE   dp.name LIKE 'role[_]%'
ORDER BY dp.name, ObjectName, p.permission_name;
GO

/* -- Run the code below if anything goes wrong in this part --
USE SmartBankProd;
GO
IF IS_ROLEMEMBER('role_DBA',        'dba_ahmad')  = 1 ALTER ROLE role_DBA        DROP MEMBER [dba_ahmad];
IF IS_ROLEMEMBER('role_Manager',    'mgr_aisyah') = 1 ALTER ROLE role_Manager    DROP MEMBER [mgr_aisyah];
IF IS_ROLEMEMBER('role_Manager',    'mgr_ravi')   = 1 ALTER ROLE role_Manager    DROP MEMBER [mgr_ravi];
IF IS_ROLEMEMBER('role_Officer',    'ofc_lim')    = 1 ALTER ROLE role_Officer    DROP MEMBER [ofc_lim];
IF IS_ROLEMEMBER('role_Officer',    'ofc_nurul')  = 1 ALTER ROLE role_Officer    DROP MEMBER [ofc_nurul];
IF IS_ROLEMEMBER('role_Customer',   'cust_tan')   = 1 ALTER ROLE role_Customer   DROP MEMBER [cust_tan];
IF IS_ROLEMEMBER('role_Customer',   'cust_siti')  = 1 ALTER ROLE role_Customer   DROP MEMBER [cust_siti];
IF IS_ROLEMEMBER('role_Customer',   'cust_kumar') = 1 ALTER ROLE role_Customer   DROP MEMBER [cust_kumar];
IF IS_ROLEMEMBER('role_Customer',   'cust_wong')  = 1 ALTER ROLE role_Customer   DROP MEMBER [cust_wong];
IF IS_ROLEMEMBER('role_ETL_Reader', 'svc_ETL')    = 1 ALTER ROLE role_ETL_Reader DROP MEMBER [svc_ETL];
GO

IF DATABASE_PRINCIPAL_ID('role_DBA')        IS NOT NULL DROP ROLE role_DBA;
IF DATABASE_PRINCIPAL_ID('role_Manager')    IS NOT NULL DROP ROLE role_Manager;
IF DATABASE_PRINCIPAL_ID('role_Officer')    IS NOT NULL DROP ROLE role_Officer;
IF DATABASE_PRINCIPAL_ID('role_Customer')   IS NOT NULL DROP ROLE role_Customer;
IF DATABASE_PRINCIPAL_ID('role_ETL_Reader') IS NOT NULL DROP ROLE role_ETL_Reader;
GO

USE SmartBankAnalytics;
GO
IF IS_ROLEMEMBER('role_ETL_Service',      'svc_ETL')     = 1 ALTER ROLE role_ETL_Service      DROP MEMBER [svc_ETL];
IF IS_ROLEMEMBER('role_Analyst_ReadOnly', 'analyst_lee') = 1 ALTER ROLE role_Analyst_ReadOnly DROP MEMBER [analyst_lee];
GO

IF DATABASE_PRINCIPAL_ID('role_ETL_Service')      IS NOT NULL DROP ROLE role_ETL_Service;
IF DATABASE_PRINCIPAL_ID('role_Analyst_ReadOnly') IS NOT NULL DROP ROLE role_Analyst_ReadOnly;
GO
*/
