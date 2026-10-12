USE master;
GO

-- Create SmartBankServer directory structure --
EXEC master.dbo.xp_create_subdir 'C:\SmartBankServer';
EXEC master.dbo.xp_create_subdir 'C:\SmartBankServer\Backup';
EXEC master.dbo.xp_create_subdir 'C:\SmartBankServer\Backup\Production';
EXEC master.dbo.xp_create_subdir 'C:\SmartBankServer\Backup\Analytics';
EXEC master.dbo.xp_create_subdir 'C:\SmartBankServer\Audit';
EXEC master.dbo.xp_create_subdir 'C:\SmartBankServer\Encryption';
GO

-- Create the production DB --
CREATE DATABASE SmartBankProd;
GO
ALTER DATABASE SmartBankProd SET RECOVERY FULL;
GO

-- Create the analytics DB --
CREATE DATABASE SmartBankAnalytics;
GO
ALTER DATABASE SmartBankAnalytics SET RECOVERY SIMPLE;
GO

-- Create "Security" schema for production DB --
USE SmartBankProd;
GO
CREATE SCHEMA [Security] AUTHORIZATION dbo;
GO

-- Create tables for production DB --
CREATE TABLE dbo.Staff (
    StaffID         VARCHAR(6)          NOT NULL    CONSTRAINT PK_Staff PRIMARY KEY,
    StaffName       VARCHAR(100)        NOT NULL,
    Position        VARCHAR(20)         NOT NULL,
    Branch          VARCHAR(50)         NOT NULL,
    Phone           VARCHAR(20)         NOT NULL,
    Salary          DECIMAL(10,2)       NOT NULL
);
GO

CREATE TABLE dbo.Customer (
    CustomerID      VARCHAR(6)          NOT NULL    CONSTRAINT PK_Customer PRIMARY KEY,
    CustomerName    VARCHAR(100)        NOT NULL,
    ICNumber        VARCHAR(20)         NOT NULL,
    Phone           VARCHAR(20)         NULL,
    [Address]       VARCHAR(200)        NULL
);
GO

CREATE TABLE dbo.Account (
    AccountID       VARCHAR(10)         NOT NULL    CONSTRAINT PK_Account PRIMARY KEY,
    CustomerID      VARCHAR(6)          NOT NULL,
    AccountType     VARCHAR(20)         NOT NULL,
    Balance         DECIMAL(12,2)       NOT NULL    CONSTRAINT DF_Account_Balance DEFAULT (0)
);
GO

CREATE TABLE dbo.TransactionRecord (
    TransID         INT IDENTITY(1,1)   NOT NULL    CONSTRAINT PK_TransactionRecord PRIMARY KEY,
    AccountID       VARCHAR(10)         NOT NULL,
    TransDate       DATETIME2(0)        NOT NULL    CONSTRAINT DF_Trans_Date DEFAULT (SYSDATETIME()),
    Amount          DECIMAL(12,2)       NOT NULL,
    TransactionType VARCHAR(20)         NOT NULL,
    ToAccountID     VARCHAR(10)         NULL,
    PerformedBy     SYSNAME             NOT NULL    CONSTRAINT DF_Trans_By DEFAULT (ORIGINAL_LOGIN())
);
GO

CREATE TABLE [Security].UserMapping (
    DatabaseUser    SYSNAME             NOT NULL    CONSTRAINT PK_UserMapping PRIMARY KEY,
    LoginName       SYSNAME             NOT NULL,
    StaffID         VARCHAR(6)          NULL,
    CustomerID      VARCHAR(6)          NULL
);
GO

CREATE TABLE [Security].RejectedAttemptLog (
    AttemptID       INT IDENTITY(1,1)   NOT NULL    CONSTRAINT PK_RejectedAttemptLog PRIMARY KEY,
    AttemptedOn     DATETIME2(0)        NOT NULL    CONSTRAINT DF_Rejected_On DEFAULT (SYSDATETIME()),
    LoginName       SYSNAME             NOT NULL,
    ProcedureName   SYSNAME             NOT NULL,
    Reason          VARCHAR(300)        NOT NULL,
    Detail          VARCHAR(500)        NULL
);
GO

-- Create "Reporting" schema for analytics DB --
USE SmartBankAnalytics;
GO
CREATE SCHEMA Reporting AUTHORIZATION dbo;
GO

-- Create tables for analytics DB --
CREATE TABLE Reporting.DimCustomer (
    CustomerHash    CHAR(64)            NOT NULL    CONSTRAINT PK_DimCustomer PRIMARY KEY,
    MaskedName      VARCHAR(100)        NOT NULL,
    LoadedOn        DATETIME2(0)        NOT NULL    CONSTRAINT DF_DimCustomer_Loaded DEFAULT (SYSDATETIME())
);
GO

CREATE TABLE Reporting.FactAccount (
    AccountHash     CHAR(64)            NOT NULL    CONSTRAINT PK_FactAccount PRIMARY KEY,
    CustomerHash    CHAR(64)            NOT NULL,
    AccountType     VARCHAR(20)         NOT NULL,
    Balance         DECIMAL(12,2)       NOT NULL,
    LoadedOn        DATETIME2(0)        NOT NULL    CONSTRAINT DF_FactAccount_Loaded DEFAULT (SYSDATETIME())
);
GO

CREATE TABLE Reporting.FactTransaction (
    TransHash       CHAR(64)            NOT NULL    CONSTRAINT PK_FactTransaction PRIMARY KEY,
    AccountHash     CHAR(64)            NOT NULL,
    TransDate       DATETIME2(0)        NOT NULL,
    Amount          DECIMAL(12,2)       NOT NULL,
    TransactionType VARCHAR(20)         NOT NULL,
    LoadedOn        DATETIME2(0)        NOT NULL    CONSTRAINT DF_FactTransaction_Loaded DEFAULT (SYSDATETIME())
);
GO

CREATE TABLE Reporting.ETLRunLog (
    RunID           INT IDENTITY(1,1)   NOT NULL    CONSTRAINT PK_ETLRunLog PRIMARY KEY,
    StartedOn       DATETIME2(0)        NOT NULL,
    CompletedOn     DATETIME2(0)        NULL,
    CustomerRows    INT                 NULL,
    AccountRows     INT                 NULL,
    TransactionRows INT                 NULL,
    RunStatus       VARCHAR(20)         NOT NULL,
    [Message]       VARCHAR(500)        NULL
);
GO

-- Populate data for tables under "dbo" schema --
USE SmartBankProd;
GO

INSERT INTO dbo.Staff (StaffID, StaffName, Position, Branch, Phone, Salary) VALUES
    ('S00001',  'Ahmad bin Hassan',     'DBA',      'HQ Kuala Lumpur',  '012-3450001',  9500.00),
    ('S00002',  'Aisyah binti Rahman',  'Manager',  'Petaling Jaya',    '012-3450002',  12000.00),
    ('S00003',  'Ravi Subramaniam',     'Manager',  'Shah Alam',        '012-3450003',  11500.00),
    ('S00004',  'Lim Wei Sheng',        'Officer',  'Petaling Jaya',    '012-3450004',  5200.00),
    ('S00005',  'Nurul Izzah',          'Officer',  'Shah Alam',        '012-3450005',  4900.00);
GO

INSERT INTO dbo.Customer (CustomerID, CustomerName, ICNumber, Phone, [Address]) VALUES
    ('C00001',  'Tan Mei Ling',     '900314-14-5521',   '013-7770001',  '12 Jalan Bukit Bintang, 55100 Kuala Lumpur'),
    ('C00002',  'Siti Nurhaliza',   '880725-10-4432',   '013-7770002',  '88 Jalan SS2/24, 47300 Petaling Jaya'),
    ('C00003',  'Kumar Rajendran',  '950612-08-3310',   '013-7770003',  '5 Persiaran Kayangan, 40100 Shah Alam'),
    ('C00004',  'Wong Kah Meng',    '011128-14-2201',   '013-7770004',  '30 Jalan Ampang, 50450 Kuala Lumpur');
GO

INSERT INTO dbo.Account (AccountID, CustomerID, AccountType, Balance) VALUES
    ('ACC1000001',  'C00001',   'Savings',  15000.00),
    ('ACC1000002',  'C00001',   'Current',  4500.00),
    ('ACC1000003',  'C00002',   'Savings',  28000.00),
    ('ACC1000004',  'C00003',   'Savings',  9200.00),
    ('ACC1000005',  'C00004',   'Current',  51000.00);
GO

INSERT INTO dbo.TransactionRecord (AccountID, TransDate, Amount, TransactionType, ToAccountID, PerformedBy) VALUES
    ('ACC1000001',  '2026-07-01 09:15:00',  2000.00,    'Deposit',      NULL,           'seed'),
    ('ACC1000001',  '2026-07-05 14:02:00',  350.00,     'Withdrawal',   NULL,           'seed'),
    ('ACC1000003',  '2026-07-06 11:40:00',  5000.00,    'Deposit',      NULL,           'seed'),
    ('ACC1000001',  '2026-07-08 09:30:00',  500.00,     'Transfer',     'ACC1000002',   'seed'),
    ('ACC1000004',  '2026-07-10 16:25:00',  120.00,     'Withdrawal',   NULL,           'seed'),
    ('ACC1000003',  '2026-07-11 13:50:00',  1000.00,    'Transfer',     'ACC1000005',   'seed'),
    ('ACC1000005',  '2026-07-12 10:05:00',  8000.00,    'Deposit',      NULL,           'seed');
GO

-- Display results (structure) --
SELECT  'SmartBankProd'                AS DatabaseName,
        s.name                         AS SchemaName,
        t.name                         AS TableName,
        t.create_date                  AS CreatedOn
FROM    SmartBankProd.sys.tables AS t
JOIN    SmartBankProd.sys.schemas AS s ON s.schema_id = t.schema_id
UNION ALL
SELECT  'SmartBankAnalytics'           AS DatabaseName,
        s.name                         AS SchemaName,
        t.name                         AS TableName,
        t.create_date                  AS CreatedOn
FROM    SmartBankAnalytics.sys.tables AS t
JOIN    SmartBankAnalytics.sys.schemas AS s ON s.schema_id = t.schema_id
ORDER BY DatabaseName, SchemaName, TableName;
GO

-- Display results (data) --
USE SmartBankProd;
GO

SELECT * FROM dbo.Staff;
SELECT * FROM dbo.Customer;
SELECT * FROM dbo.Account;
SELECT * FROM dbo.TransactionRecord;
GO

/*-- Run this if the database goes wrong and requires a refresh --
USE master;
GO

IF DB_ID('SmartBankProd') IS NOT NULL
BEGIN
    ALTER DATABASE SmartBankProd SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SmartBankProd;
END

IF DB_ID('SmartBankAnalytics') IS NOT NULL
BEGIN
    ALTER DATABASE SmartBankAnalytics SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SmartBankAnalytics;
END
*/
