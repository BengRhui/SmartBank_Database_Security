
-- Define views for production database --
USE SmartBankProd;
GO

-- A helper function is created to retrieve all staff information without RLS --
CREATE FUNCTION dbo.fn_StaffDirectory()
RETURNS @Directory TABLE
(
    StaffID   VARCHAR(6),
    StaffName VARCHAR(100),
    Phone     VARCHAR(20),
    Branch    VARCHAR(50)
)
WITH EXECUTE AS OWNER
AS
BEGIN
    INSERT INTO @Directory (StaffID, StaffName, Phone, Branch)
    SELECT StaffID, StaffName, Phone, Branch
    FROM   dbo.Staff;          -- NOTE: Salary is deliberately NOT selected
    RETURN;
END;
GO

-- The view to retrieve staff information --
CREATE VIEW dbo.vw_StaffDirectory
AS
    SELECT StaffID, StaffName, Phone, Branch
    FROM   dbo.fn_StaffDirectory();
GO

-- The view to retrieve own staff record --
CREATE VIEW dbo.vw_MyStaffRecord
AS
    SELECT s.StaffID, s.StaffName, s.Position, s.Branch, s.Phone, s.Salary
    FROM   dbo.Staff AS s
    INNER JOIN Security.UserMapping AS m ON s.StaffID = m.StaffID
    WHERE  m.DatabaseUser = USER_NAME();
GO

-- The view to retrieve all information of staff --
CREATE VIEW dbo.vw_AllStaff
AS
    SELECT StaffID, StaffName, Position, Branch, Phone, Salary
    FROM   dbo.Staff;
GO

-- The view to retrieve customer profile --
CREATE VIEW dbo.vw_CustomerProfile
AS
    SELECT CustomerID, CustomerName, Phone, [Address]
    FROM   dbo.Customer;
GO

-- The view to retrieve customer account details --
CREATE VIEW dbo.vw_CustomerAccounts
AS
    SELECT  a.AccountID,
            a.CustomerID,
            a.AccountType,
            a.Balance
    FROM    dbo.Account AS a;
GO

-- The view to retrieve customer transaction details --
CREATE VIEW dbo.vw_CustomerTransactions
AS
    SELECT  t.TransID,
            t.AccountID,
            t.TransDate,
            t.Amount,
            t.TransactionType,
            t.ToAccountID
    FROM    dbo.TransactionRecord AS t;
GO

-- Grant access to respective roles based on authorisation matrix --
GRANT SELECT ON dbo.vw_StaffDirectory       TO role_DBA, role_Manager, role_Officer, role_Customer;
GRANT SELECT ON dbo.vw_MyStaffRecord        TO role_DBA, role_Manager, role_Officer;
GRANT SELECT ON dbo.vw_AllStaff             TO role_Manager;
DENY  SELECT ON dbo.vw_AllStaff             TO role_DBA, role_Officer, role_Customer;
GRANT SELECT ON dbo.vw_CustomerProfile      TO role_Manager, role_Officer;
DENY  SELECT ON dbo.vw_CustomerProfile      TO role_DBA, role_Customer;
GRANT SELECT ON dbo.vw_CustomerAccounts     TO role_Manager, role_Officer, role_Customer;
DENY  SELECT ON dbo.vw_CustomerAccounts     TO role_DBA;
GRANT SELECT ON dbo.vw_CustomerTransactions TO role_Manager, role_Officer, role_Customer;
DENY  SELECT ON dbo.vw_CustomerTransactions TO role_DBA;
GO

-- Validate that views are assigned to roles accordingly --
SELECT  v.name  AS ViewName,
        dp.name AS RoleName,
        p.permission_name,
        p.state_desc AS GrantOrDeny
FROM    sys.database_permissions p
JOIN    sys.views v                ON v.object_id = p.major_id
JOIN    sys.database_principals dp ON dp.principal_id = p.grantee_principal_id
ORDER BY v.name, dp.name;
GO

-- Test to check if views are functioning -- 
EXECUTE AS USER = 'ofc_lim';
    SELECT USER_NAME() AS RunningAs, * FROM dbo.vw_StaffDirectory;
REVERT;
GO

EXECUTE AS USER = 'cust_tan';
    SELECT USER_NAME() AS RunningAs, * FROM dbo.vw_CustomerTransactions;
REVERT;
GO

EXECUTE AS USER = 'cust_siti';
    SELECT USER_NAME() AS RunningAs, * FROM dbo.vw_CustomerTransactions;
REVERT;
GO

/* -- Run the code below if anything goes wrong --
USE SmartBankProd;
GO

IF OBJECT_ID('dbo.vw_StaffDirectory')       IS NOT NULL DROP VIEW dbo.vw_StaffDirectory;
IF OBJECT_ID('dbo.vw_MyStaffRecord')        IS NOT NULL DROP VIEW dbo.vw_MyStaffRecord;
IF OBJECT_ID('dbo.vw_AllStaff')             IS NOT NULL DROP VIEW dbo.vw_AllStaff;
IF OBJECT_ID('dbo.vw_CustomerProfile')      IS NOT NULL DROP VIEW dbo.vw_CustomerProfile;
IF OBJECT_ID('dbo.vw_CustomerAccounts')     IS NOT NULL DROP VIEW dbo.vw_CustomerAccounts;
IF OBJECT_ID('dbo.vw_CustomerTransactions') IS NOT NULL DROP VIEW dbo.vw_CustomerTransactions;
GO

IF OBJECT_ID('dbo.fn_StaffDirectory') IS NOT NULL DROP FUNCTION dbo.fn_StaffDirectory;
GO
*/
