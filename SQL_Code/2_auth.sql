
-- Create logins (server level) --
USE master;
GO

-- Staff logins
CREATE LOGIN [dba_ahmad]   WITH PASSWORD = 'SmartBank@2026#Dba'  MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;
CREATE LOGIN [mgr_aisyah]  WITH PASSWORD = 'SmartBank@2026#Mgr1' MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;
CREATE LOGIN [mgr_ravi]    WITH PASSWORD = 'SmartBank@2026#Mgr2' MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;
CREATE LOGIN [ofc_lim]     WITH PASSWORD = 'SmartBank@2026#Ofc1' MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;
CREATE LOGIN [ofc_nurul]   WITH PASSWORD = 'SmartBank@2026#Ofc2' MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;

-- Customer logins
CREATE LOGIN [cust_tan]    WITH PASSWORD = 'SmartBank@2026#Cus1' MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;
CREATE LOGIN [cust_siti]   WITH PASSWORD = 'SmartBank@2026#Cus2' MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;
CREATE LOGIN [cust_kumar]  WITH PASSWORD = 'SmartBank@2026#Cus3' MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;
CREATE LOGIN [cust_wong]   WITH PASSWORD = 'SmartBank@2026#Cus4' MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;

-- Analytics side
CREATE LOGIN [analyst_lee] WITH PASSWORD = 'SmartBank@2026#Ana1' MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;

-- Special: svc_ETL is a service account, so does not require expiration
CREATE LOGIN [svc_ETL]     WITH PASSWORD = 'SmartBank@2026#Etl0', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
GO

-- Create users for production DB (database-level) --
USE SmartBankProd;
GO

CREATE USER [dba_ahmad]  FOR LOGIN [dba_ahmad];
CREATE USER [mgr_aisyah] FOR LOGIN [mgr_aisyah];
CREATE USER [mgr_ravi]   FOR LOGIN [mgr_ravi];
CREATE USER [ofc_lim]    FOR LOGIN [ofc_lim];
CREATE USER [ofc_nurul]  FOR LOGIN [ofc_nurul];
CREATE USER [cust_tan]   FOR LOGIN [cust_tan];
CREATE USER [cust_siti]  FOR LOGIN [cust_siti];
CREATE USER [cust_kumar] FOR LOGIN [cust_kumar];
CREATE USER [cust_wong]  FOR LOGIN [cust_wong];
CREATE USER [svc_ETL]    FOR LOGIN [svc_ETL];
GO

-- Create users for analytics DB (database-level) --
USE SmartBankAnalytics;
GO

CREATE USER [svc_ETL]     FOR LOGIN [svc_ETL];
CREATE USER [analyst_lee] FOR LOGIN [analyst_lee];
GO

-- A table to map logged-in production users to their PKs --
USE SmartBankProd;
GO
INSERT INTO Security.UserMapping (DatabaseUser, LoginName, StaffID, CustomerID) VALUES
    ('dba_ahmad',  'dba_ahmad',  'S00001', NULL),
    ('mgr_aisyah', 'mgr_aisyah', 'S00002', NULL),
    ('mgr_ravi',   'mgr_ravi',   'S00003', NULL),
    ('ofc_lim',    'ofc_lim',    'S00004', NULL),
    ('ofc_nurul',  'ofc_nurul',  'S00005', NULL),
    ('cust_tan',   'cust_tan',   NULL, 'C00001'),
    ('cust_siti',  'cust_siti',  NULL, 'C00002'),
    ('cust_kumar', 'cust_kumar', NULL, 'C00003'),
    ('cust_wong',  'cust_wong',  NULL, 'C00004'),
    ('svc_ETL',    'svc_ETL',    NULL, NULL);
GO

-- Add unique index to ensure values are unique --
CREATE UNIQUE INDEX UQ_UserMapping_LoginName  ON Security.UserMapping (LoginName);
CREATE UNIQUE INDEX UQ_UserMapping_StaffID    ON Security.UserMapping (StaffID) WHERE StaffID IS NOT NULL;
CREATE UNIQUE INDEX UQ_UserMapping_CustomerID ON Security.UserMapping (CustomerID) WHERE CustomerID IS NOT NULL;
GO

-- Create a new system admin account --
USE master;
GO

CREATE LOGIN [smartbank_admin] WITH PASSWORD = 'SmartBank@2026#Adm1' MUST_CHANGE, CHECK_POLICY = ON, CHECK_EXPIRATION = ON;
GO
ALTER SERVER ROLE [sysadmin] ADD MEMBER [smartbank_admin];
GO

-- Check if smartbank_admin is successfully created as 'sa' --
SELECT IS_SRVROLEMEMBER('sysadmin', 'smartbank_admin') AS IsSysadmin;
GO

-- Disable default 'sa' account --
ALTER LOGIN [sa] DISABLE;
GO

-- Disable current Windows Auth account --
ALTER LOGIN [LIMBENGRHUIC674\limbengrhui] DISABLE;
GO
ALTER SERVER ROLE sysadmin DROP MEMBER [LIMBENGRHUIC674\limbengrhui];
GO

-- Show the details of the users who are allowed to login --
SELECT  name                  AS LoginName,
        is_policy_checked     AS PasswordPolicyEnforced,
        is_expiration_checked AS ExpirationEnforced,
        is_disabled           AS IsDisabled,
        create_date
FROM    sys.sql_logins
WHERE   (name LIKE 'dba[_]%' OR name LIKE 'mgr[_]%' OR name LIKE 'ofc[_]%'
     OR name LIKE 'cust[_]%' OR name LIKE 'analyst[_]%' OR name = 'svc_ETL'
     OR name = 'smartbank_admin' OR name = 'sa')
ORDER BY is_disabled, name;
GO

-- Show the table that maps each login to the respective staff ID or customer ID --
USE SmartBankProd;
GO
SELECT  dp.name         AS DatabaseUser,
        sp.name         AS ServerLogin,
        m.StaffID,
        m.CustomerID
FROM    sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp ON sp.sid = dp.sid
LEFT JOIN Security.UserMapping  AS m  ON m.DatabaseUser = dp.name
WHERE   dp.type = 'S' AND dp.principal_id > 4
ORDER BY dp.name;
GO

/*-- Run this code to remove existing users if anything goes wrong
USE SmartBankProd;
GO
IF DATABASE_PRINCIPAL_ID('dba_ahmad')  IS NOT NULL DROP USER [dba_ahmad];
IF DATABASE_PRINCIPAL_ID('mgr_aisyah') IS NOT NULL DROP USER [mgr_aisyah];
IF DATABASE_PRINCIPAL_ID('mgr_ravi')   IS NOT NULL DROP USER [mgr_ravi];
IF DATABASE_PRINCIPAL_ID('ofc_lim')    IS NOT NULL DROP USER [ofc_lim];
IF DATABASE_PRINCIPAL_ID('ofc_nurul')  IS NOT NULL DROP USER [ofc_nurul];
IF DATABASE_PRINCIPAL_ID('cust_tan')   IS NOT NULL DROP USER [cust_tan];
IF DATABASE_PRINCIPAL_ID('cust_siti')  IS NOT NULL DROP USER [cust_siti];
IF DATABASE_PRINCIPAL_ID('cust_kumar') IS NOT NULL DROP USER [cust_kumar];
IF DATABASE_PRINCIPAL_ID('cust_wong')  IS NOT NULL DROP USER [cust_wong];
IF DATABASE_PRINCIPAL_ID('svc_ETL')    IS NOT NULL DROP USER [svc_ETL];
GO

USE SmartBankAnalytics;
GO
IF DATABASE_PRINCIPAL_ID('svc_ETL')     IS NOT NULL DROP USER [svc_ETL];
IF DATABASE_PRINCIPAL_ID('analyst_lee') IS NOT NULL DROP USER [analyst_lee];
GO

USE SmartBankProd;
GO
DROP INDEX IF EXISTS UQ_UserMapping_LoginName  ON Security.UserMapping;
DROP INDEX IF EXISTS UQ_UserMapping_StaffID    ON Security.UserMapping;
DROP INDEX IF EXISTS UQ_UserMapping_CustomerID ON Security.UserMapping;
DELETE FROM Security.UserMapping;
GO

USE master;
GO
IF SUSER_ID('dba_ahmad')        IS NOT NULL DROP LOGIN [dba_ahmad];
IF SUSER_ID('mgr_aisyah')       IS NOT NULL DROP LOGIN [mgr_aisyah];
IF SUSER_ID('mgr_ravi')         IS NOT NULL DROP LOGIN [mgr_ravi];
IF SUSER_ID('ofc_lim')          IS NOT NULL DROP LOGIN [ofc_lim];
IF SUSER_ID('ofc_nurul')        IS NOT NULL DROP LOGIN [ofc_nurul];
IF SUSER_ID('cust_tan')         IS NOT NULL DROP LOGIN [cust_tan];
IF SUSER_ID('cust_siti')        IS NOT NULL DROP LOGIN [cust_siti];
IF SUSER_ID('cust_kumar')       IS NOT NULL DROP LOGIN [cust_kumar];
IF SUSER_ID('cust_wong')        IS NOT NULL DROP LOGIN [cust_wong];
IF SUSER_ID('analyst_lee')      IS NOT NULL DROP LOGIN [analyst_lee];
IF SUSER_ID('svc_ETL')          IS NOT NULL DROP LOGIN [svc_ETL];
IF SUSER_ID('smartbank_admin')  IS NOT NULL DROP LOGIN [smartbank_admin];
GO
*/
