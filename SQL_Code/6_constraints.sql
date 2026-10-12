
-- Foreign key constraints (production DB)--
USE SmartBankProd;
GO

ALTER TABLE dbo.Account
    ADD CONSTRAINT FK_Account_Customer
    FOREIGN KEY (CustomerID) REFERENCES dbo.Customer (CustomerID);

ALTER TABLE dbo.TransactionRecord
    ADD CONSTRAINT FK_Transaction_Account
    FOREIGN KEY (AccountID) REFERENCES dbo.Account (AccountID);

ALTER TABLE dbo.TransactionRecord
    ADD CONSTRAINT FK_Transaction_ToAccount
    FOREIGN KEY (ToAccountID) REFERENCES dbo.Account (AccountID);
GO

-- Foreign key constraints (analytics DB)--
USE SmartBankAnalytics;
GO

ALTER TABLE Reporting.FactAccount
    ADD CONSTRAINT FK_FactAccount_DimCustomer
    FOREIGN KEY (CustomerHash) REFERENCES Reporting.DimCustomer (CustomerHash);

ALTER TABLE Reporting.FactTransaction 
    ADD CONSTRAINT FK_FactTransaction_FactAccount
    FOREIGN KEY (AccountHash) REFERENCES Reporting.FactAccount (AccountHash);
GO

-- Check constraints (production DB) --
USE SmartBankProd;
GO

ALTER TABLE dbo.Account
    ADD CONSTRAINT CK_Account_BalanceNonNegative
    CHECK (Balance >= 0);

ALTER TABLE dbo.Account
    ADD CONSTRAINT CK_Account_Type
    CHECK (AccountType IN ('Savings', 'Current'));

ALTER TABLE dbo.Staff
    ADD CONSTRAINT CK_Staff_Position
    CHECK (Position IN ('DBA', 'Manager', 'Officer'));

ALTER TABLE dbo.Staff
    ADD CONSTRAINT CK_Staff_SalaryNonNegative
    CHECK (Salary >= 0);

ALTER TABLE dbo.TransactionRecord
    ADD CONSTRAINT CK_Transaction_Type
    CHECK (TransactionType IN ('Deposit', 'Withdrawal', 'Transfer'));

ALTER TABLE dbo.TransactionRecord
    ADD CONSTRAINT CK_Transaction_AmountPositive
    CHECK (Amount > 0);

ALTER TABLE dbo.TransactionRecord
    ADD CONSTRAINT CK_Transaction_ToAccountNotSelf
    CHECK (ToAccountID IS NULL OR ToAccountID <> AccountID);

ALTER TABLE dbo.TransactionRecord
    ADD CONSTRAINT CK_Transaction_ToAccountLogic
    CHECK ((TransactionType = 'Transfer' AND ToAccountID IS NOT NULL)
           OR (TransactionType <> 'Transfer' AND ToAccountID IS NULL)
    );

ALTER TABLE Security.UserMapping
    ADD CONSTRAINT CK_UserMapping_OneIdentity
    CHECK ((StaffID IS NOT NULL AND CustomerID IS NULL)
           OR (StaffID IS NULL AND CustomerID IS NOT NULL)
           OR (StaffID IS NULL AND CustomerID IS NULL)         -- This is for service accounts
    );
GO

-- Check constraints (analytics DB) --
USE SmartBankAnalytics;
GO

ALTER TABLE Reporting.ETLRunLog
    ADD CONSTRAINT CK_ETLRunLog_RunStatus
    CHECK (RunStatus IN ('Running', 'Success', 'Failed'));
GO

-- Verification that FK and check constraints are implemented (production DB) --
USE SmartBankProd;
GO

SELECT  OBJECT_SCHEMA_NAME(parent_object_id) AS SchemaName,
        OBJECT_NAME(parent_object_id)        AS TableName,
        name                                 AS ConstraintName,
        type_desc                            AS ConstraintType
FROM    sys.objects
WHERE   type IN ('F', 'C')
ORDER BY TableName, ConstraintType, ConstraintName;
GO

-- Verification that FK and check constraints are implemented (analytics DB) --
USE SmartBankAnalytics;
GO

SELECT  OBJECT_SCHEMA_NAME(parent_object_id) AS SchemaName,
        OBJECT_NAME(parent_object_id)        AS TableName,
        name                                 AS ConstraintName,
        type_desc                            AS ConstraintType
FROM    sys.objects
WHERE   type IN ('F', 'C')                       -- foreign key, check
ORDER BY TableName, ConstraintType, ConstraintName;
GO

-- Quick test to demonstrate that FK and check constraint works --
USE SmartBankProd;
GO

BEGIN TRAN;
BEGIN TRY
    INSERT INTO dbo.Account (AccountID, CustomerID, AccountType, Balance)
    VALUES ('ACC9999999', 'C99999', 'Savings', 100.00);
    SELECT 'FAILED - orphan account was accepted' AS Result;
END TRY
BEGIN CATCH
    SELECT 'PASSED - FK_Account_Customer blocked the orphan' AS Result,
           ERROR_MESSAGE() AS ErrorMessage;
END CATCH
ROLLBACK TRAN;
GO

BEGIN TRAN;
BEGIN TRY
    INSERT INTO dbo.TransactionRecord (AccountID, Amount, TransactionType)
    VALUES ('ACC1000001', 100.00, 'Random type');
    SELECT 'FAILED - invalid transaction type was accepted' AS Result;
END TRY
BEGIN CATCH
    SELECT 'PASSED - CK_Transaction_Type rejected the value' AS Result,
           ERROR_MESSAGE() AS ErrorMessage;
END CATCH
ROLLBACK TRAN;
GO

/* -- Run the code below if anything goes wrong --
USE SmartBankProd;
GO

ALTER TABLE Security.UserMapping  DROP CONSTRAINT CK_UserMapping_OneIdentity;
ALTER TABLE dbo.TransactionRecord DROP CONSTRAINT CK_Transaction_ToAccountLogic;
ALTER TABLE dbo.TransactionRecord DROP CONSTRAINT CK_Transaction_ToAccountNotSelf;
ALTER TABLE dbo.TransactionRecord DROP CONSTRAINT CK_Transaction_AmountPositive;
ALTER TABLE dbo.TransactionRecord DROP CONSTRAINT CK_Transaction_Type;
ALTER TABLE dbo.Staff             DROP CONSTRAINT CK_Staff_SalaryNonNegative;
ALTER TABLE dbo.Staff             DROP CONSTRAINT CK_Staff_Position;
ALTER TABLE dbo.Account           DROP CONSTRAINT CK_Account_Type;
ALTER TABLE dbo.Account           DROP CONSTRAINT CK_Account_BalanceNonNegative;
ALTER TABLE dbo.TransactionRecord DROP CONSTRAINT FK_Transaction_ToAccount;
ALTER TABLE dbo.TransactionRecord DROP CONSTRAINT FK_Transaction_Account;
ALTER TABLE dbo.Account           DROP CONSTRAINT FK_Account_Customer;
GO

USE SmartBankAnalytics;
GO

ALTER TABLE Reporting.ETLRunLog       DROP CONSTRAINT CK_ETLRunLog_RunStatus;
ALTER TABLE Reporting.FactTransaction DROP CONSTRAINT FK_FactTransaction_FactAccount;
ALTER TABLE Reporting.FactAccount     DROP CONSTRAINT FK_FactAccount_DimCustomer;
GO
*/
