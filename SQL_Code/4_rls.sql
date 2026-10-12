
-- Perform RLS on production DB --
USE SmartBankProd;
GO

-- Predicate function for customers --
CREATE FUNCTION [Security].fn_CustomerAccessPredicate (@CustomerID AS VARCHAR(6))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS fn_AccessResult
    WHERE
           USER_NAME() = 'dbo'
        OR IS_MEMBER('db_owner') = 1
        OR IS_MEMBER('role_ETL_Reader') = 1
        OR IS_MEMBER('role_Manager') = 1
        OR IS_MEMBER('role_Officer') = 1                -- System admin, ETL extractor, manager and officer can see customer profile
        OR EXISTS (
               SELECT 1
               FROM   Security.UserMapping AS m
               WHERE  m.DatabaseUser = USER_NAME()
                 AND  m.CustomerID   = @CustomerID      -- Customer can only see their own profile
           );
GO

-- Security policy for customers --
CREATE SECURITY POLICY [Security].CustomerSecurityPolicy
    ADD FILTER PREDICATE [Security].fn_CustomerAccessPredicate(CustomerID) ON dbo.Customer,
    ADD BLOCK  PREDICATE [Security].fn_CustomerAccessPredicate(CustomerID) ON dbo.Customer AFTER UPDATE
WITH (STATE = ON);
GO

-- Predicate function for accounts --
CREATE FUNCTION [Security].fn_AccountAccessPredicate (@CustomerID AS VARCHAR(6))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS fn_AccessResult
    WHERE
           USER_NAME() = 'dbo'
        OR IS_MEMBER('db_owner') = 1
        OR IS_MEMBER('role_ETL_Reader') = 1
        OR IS_MEMBER('role_Manager') = 1
        OR IS_MEMBER('role_Officer') = 1             -- System admin, ETL extractor, manager and officer can view all accounts 
        OR EXISTS (                                  
               SELECT 1
               FROM   Security.UserMapping AS m
               WHERE  m.DatabaseUser = USER_NAME()   -- Customers can only view their own accounts
                 AND  m.CustomerID   = @CustomerID
           );
GO

-- Security policy for accounts --
CREATE SECURITY POLICY [Security].AccountSecurityPolicy
    ADD FILTER PREDICATE [Security].fn_AccountAccessPredicate(CustomerID) ON dbo.Account,
    ADD BLOCK  PREDICATE [Security].fn_AccountAccessPredicate(CustomerID) ON dbo.Account AFTER UPDATE
WITH (STATE = ON);
GO

-- Predicate function for transaction records --
CREATE FUNCTION [Security].fn_TransactionAccessPredicate
(
    @AccountID             AS VARCHAR(10),
    @ToAccountID AS VARCHAR(10)
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS fn_AccessResult
    WHERE
           USER_NAME() = 'dbo'
        OR IS_MEMBER('db_owner') = 1
        OR IS_MEMBER('role_ETL_Reader') = 1
        OR IS_MEMBER('role_Manager') = 1
        OR IS_MEMBER('role_Officer') = 1                          -- System admin, ETL extractor, manager and officer can view all transaction
        OR EXISTS (
               SELECT 1
               FROM   Security.UserMapping AS m
               INNER JOIN dbo.Account AS a
                       ON a.CustomerID = m.CustomerID
               WHERE  m.DatabaseUser = USER_NAME()
                 AND  a.AccountID IN (@AccountID, @ToAccountID)   -- Customers (as a sender and recipient) can view relevant transaction
           );
GO

-- Security policy for transaction records --
CREATE SECURITY POLICY [Security].TransactionSecurityPolicy
    ADD FILTER PREDICATE [Security].fn_TransactionAccessPredicate(AccountID, ToAccountID) ON dbo.TransactionRecord,
    ADD BLOCK PREDICATE [Security].fn_TransactionAccessPredicate(AccountID, ToAccountID) ON dbo.TransactionRecord AFTER INSERT,
    ADD BLOCK PREDICATE [Security].fn_TransactionAccessPredicate(AccountID, ToAccountID) ON dbo.TransactionRecord AFTER UPDATE
WITH (STATE = ON);
GO

-- Predicate function for staff --
CREATE FUNCTION [Security].fn_StaffAccessPredicate (@StaffID AS VARCHAR(6))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS fn_AccessResult
    WHERE
           USER_NAME() = 'dbo'
        OR IS_MEMBER('db_owner') = 1
        OR IS_MEMBER('role_Manager') = 1             -- Only system admins and manager can view all records
        OR EXISTS (
               SELECT 1
               FROM   Security.UserMapping AS m
               WHERE  m.DatabaseUser = USER_NAME()   -- Others can only view their own records
                 AND  m.StaffID      = @StaffID
           );
GO

-- Security policy for staff --
CREATE SECURITY POLICY [Security].StaffSecurityPolicy
    ADD FILTER PREDICATE [Security].fn_StaffAccessPredicate(StaffID) ON dbo.Staff,
    ADD BLOCK  PREDICATE [Security].fn_StaffAccessPredicate(StaffID) ON dbo.Staff AFTER UPDATE
WITH (STATE = ON);
GO

-- Predicate function for User Mapping table --
CREATE FUNCTION [Security].fn_UserMappingPredicate (@DatabaseUser AS SYSNAME)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS fn_AccessResult
    WHERE
           USER_NAME() = 'dbo'
        OR IS_MEMBER('db_owner')    = 1
        OR @DatabaseUser = USER_NAME();                 -- Shall be able to check on own records only
GO

-- Security policy for User Mapping table --
CREATE SECURITY POLICY [Security].UserMappingSecurityPolicy
    ADD FILTER PREDICATE [Security].fn_UserMappingPredicate(DatabaseUser) ON [Security].UserMapping
WITH (STATE = ON);
GO

-- Verification --
USE SmartBankProd;
GO

-- Display the security policies that are being enforced --
SELECT  sp.name                           AS PolicyName,
        sp.is_enabled,
        OBJECT_NAME(spr.target_object_id)  AS ProtectedTable,
        spr.predicate_type_desc,
        spr.predicate_definition
FROM    sys.security_policies AS sp
JOIN    sys.security_predicates AS spr
     ON  spr.object_id = sp.object_id
ORDER BY PolicyName, ProtectedTable;
GO

-- A simple demo for RLS --
GRANT SELECT ON dbo.Account TO role_Customer;       -- Temporarily grant access to view accounts
GO

EXECUTE AS USER = 'cust_tan';
    SELECT USER_NAME() AS RunningAs, AccountID, CustomerID, Balance FROM dbo.Account;
REVERT;
GO

EXECUTE AS USER = 'cust_siti';
    SELECT USER_NAME() AS RunningAs, AccountID, CustomerID, Balance FROM dbo.Account;
REVERT;
GO

DENY SELECT ON dbo.Account TO role_Customer;      -- Must immediately deny access once done to align with RBAC
GO

-- Ensure that the svc_ETL account is able to access all data to support ETL pipeline --
EXECUTE AS USER = 'svc_ETL';
    SELECT  USER_NAME()                                       AS RunningAs,
            (SELECT COUNT(*) FROM dbo.Customer)               AS CustomersVisible,
            (SELECT COUNT(*) FROM dbo.Account)                AS AccountsVisible,
            (SELECT COUNT(*) FROM dbo.TransactionRecord)      AS TransactionsVisible;
REVERT;
GO

/* -- Run below if anything goes wrong --
USE SmartBankProd;
GO
IF OBJECT_ID('Security.StaffSecurityPolicy')       IS NOT NULL DROP SECURITY POLICY Security.StaffSecurityPolicy;
IF OBJECT_ID('Security.AccountSecurityPolicy')     IS NOT NULL DROP SECURITY POLICY Security.AccountSecurityPolicy;
IF OBJECT_ID('Security.TransactionSecurityPolicy') IS NOT NULL DROP SECURITY POLICY Security.TransactionSecurityPolicy;
IF OBJECT_ID('Security.CustomerSecurityPolicy')    IS NOT NULL DROP SECURITY POLICY Security.CustomerSecurityPolicy;
GO

IF OBJECT_ID('Security.fn_StaffAccessPredicate')       IS NOT NULL DROP FUNCTION Security.fn_StaffAccessPredicate;
IF OBJECT_ID('Security.fn_AccountAccessPredicate')     IS NOT NULL DROP FUNCTION Security.fn_AccountAccessPredicate;
IF OBJECT_ID('Security.fn_TransactionAccessPredicate') IS NOT NULL DROP FUNCTION Security.fn_TransactionAccessPredicate;
IF OBJECT_ID('Security.fn_CustomerAccessPredicate')    IS NOT NULL DROP FUNCTION Security.fn_CustomerAccessPredicate;
GO
*/
