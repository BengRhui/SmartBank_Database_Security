
-- Stored procedures for production DB --
USE SmartBankProd;
GO

-- Stored procedure to record rejected actions --
CREATE PROCEDURE [Security].usp_LogRejection
    @ProcedureName SYSNAME,
    @Reason        VARCHAR(300),
    @Detail        VARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;                             -- This is to close the message generated when performing actions
    INSERT INTO Security.RejectedAttemptLog (LoginName, ProcedureName, Reason, Detail)
    VALUES (ORIGINAL_LOGIN(), @ProcedureName, @Reason, @Detail);
END;
GO

-- Stored procedure for deposit money --
CREATE PROCEDURE dbo.usp_Deposit
    @AccountID VARCHAR(10),
    @Amount    DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;                          -- Force SQL to reroll the entire transaction if anything goes wrong

    DECLARE @Caller SYSNAME = ORIGINAL_LOGIN(); -- Required to capture the person who login to SQL
    DECLARE @CallerCustomerID VARCHAR(6);

    BEGIN TRY
        
        -- Check if current user is a customer, reject immediately if no --
        IF IS_ROLEMEMBER('role_Customer', @Caller) <> 1
        BEGIN
            EXEC [Security].usp_LogRejection 'usp_Deposit',
                                             'Caller is not a member of role_Customer', 
                                             @AccountID;
            THROW 51001, 'Only customers may perform transactions.', 1;
        END

        -- Retrieve the customer ID --
        SELECT @CallerCustomerID = m.CustomerID
        FROM   [Security].UserMapping AS m
        WHERE  m.LoginName = @Caller;

        -- Check if the account ID belongs to the customer, reject if not --
        IF NOT EXISTS (SELECT 1 FROM dbo.Account
                       WHERE AccountID = @AccountID
                         AND CustomerID = @CallerCustomerID)
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Deposit',
                                           'Account does not belong to caller', 
                                           @AccountID;
            THROW 51002, 'You may only transact on your own account.', 1;
        END

        -- Validate the amount entered, reject if not more than 0 --
        IF @Amount <= 0
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Deposit',
                                           'Non-positive amount', 
                                           @AccountID;
            THROW 51003, 'Deposit amount must be greater than zero.', 1;
        END

        -- Everything checked, can begin deposit action --
        BEGIN TRANSACTION;

            -- Update the balance of the account --
            UPDATE dbo.Account
            SET    Balance = Balance + @Amount
            WHERE  AccountID = @AccountID;

            -- Record the transaction --
            INSERT INTO dbo.TransactionRecord
                   (AccountID, Amount, TransactionType, PerformedBy)
            VALUES (@AccountID, @Amount, 'Deposit', @Caller);

        COMMIT TRANSACTION;

        -- Output success message once done --
        PRINT 'Deposit successful.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- Rollback if there is existing transaction
        THROW;                                     -- Throw the error code from the TRY block
    END CATCH
END;
GO

-- Stored procedure for withdrawal --
CREATE PROCEDURE dbo.usp_Withdraw
    @AccountID VARCHAR(10),
    @Amount    DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Retrieve user detail --
    DECLARE @Caller SYSNAME = ORIGINAL_LOGIN();
    DECLARE @CallerCustomerID VARCHAR(6);
    DECLARE @Balance DECIMAL(12,2);

    BEGIN TRY

        -- Reject if user is not customer --
        IF IS_ROLEMEMBER('role_Customer', @Caller) <> 1
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Withdraw',
                                           'Caller is not a member of role_Customer', 
                                           @AccountID;
            THROW 51001, 'Only customers may perform transactions.', 1;
        END

        -- Extract customer ID --
        SELECT @CallerCustomerID = m.CustomerID
        FROM   Security.UserMapping AS m
        WHERE  m.LoginName = @Caller;

        -- Reject if the account does not belong to the customer --
        IF NOT EXISTS (SELECT 1 FROM dbo.Account
                       WHERE AccountID = @AccountID
                         AND CustomerID = @CallerCustomerID)
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Withdraw',
                                           'Account does not belong to caller', 
                                           @AccountID;
            THROW 51002, 'You may only transact on your own account.', 1;
        END

        -- Reject if the withdrawal amount is not more than 0 --
        IF @Amount <= 0
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Withdraw',
                                           'Non-positive amount',
                                           @AccountID;
            THROW 51003, 'Withdrawal amount must be greater than zero.', 1;
        END

        -- Retrieve account balance and check if it is sufficient for withdrawal --
        SELECT @Balance = Balance FROM dbo.Account WHERE AccountID = @AccountID;
        IF @Balance < @Amount
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Withdraw',
                                           'Insufficient funds',
                                           @AccountID;
            THROW 51004, 'Insufficient funds for this withdrawal.', 1;
        END

        -- Perform withdrawal process if everything is okay --
        BEGIN TRANSACTION;

            -- Update the latest balance --
            UPDATE dbo.Account
            SET    Balance = Balance - @Amount
            WHERE  AccountID = @AccountID;

            -- Record into the transaction record table --
            INSERT INTO dbo.TransactionRecord
                   (AccountID, Amount, TransactionType, PerformedBy)
            VALUES (@AccountID, @Amount, 'Withdrawal', @Caller);

        COMMIT TRANSACTION;

        -- Print message indicating that operation is successful --
        PRINT 'Withdrawal successful.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- Stored procedure for transfer --
CREATE PROCEDURE dbo.usp_Transfer
    @FromAccountID VARCHAR(10),
    @ToAccountID   VARCHAR(10),
    @Amount        DECIMAL(12,2)
WITH EXECUTE AS OWNER                              -- This is to override RLS to be able to update the destination account
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Extract user details --
    DECLARE @Caller SYSNAME = ORIGINAL_LOGIN();
    DECLARE @CallerCustomerID VARCHAR(6);
    DECLARE @Balance DECIMAL(12,2);

    BEGIN TRY

        -- Reject if user is not a customer --
        IF IS_ROLEMEMBER('role_Customer', @Caller) <> 1
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Transfer',
                                           'Caller is not a member of role_Customer', 
                                           @FromAccountID;
            THROW 51001, 'Only customers may perform transactions.', 1;
        END

        -- Extract customer ID --
        SELECT @CallerCustomerID = m.CustomerID
        FROM   Security.UserMapping AS m
        WHERE  m.LoginName = @Caller;

        -- Reject if the account does not belong to customer --
        IF NOT EXISTS (SELECT 1 FROM dbo.Account
                       WHERE AccountID = @FromAccountID
                         AND CustomerID = @CallerCustomerID)
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Transfer',
                                           'Source account does not belong to caller', 
                                           @FromAccountID;
            THROW 51002, 'You may only transfer from your own account.', 1;
        END

        -- Reject is source account is the same as destination account --
        IF @FromAccountID = @ToAccountID
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Transfer',
                                           'Source and destination are the same', 
                                           @FromAccountID;
            THROW 51005, 'Source and destination accounts must differ.', 1;
        END

        -- Validate if the destination account exists in database --
        IF NOT EXISTS (SELECT 1 FROM dbo.Account WHERE AccountID = @ToAccountID)
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Transfer',
                                           'Destination account does not exist',
                                           @ToAccountID;
            THROW 51006, 'Destination account does not exist.', 1;
        END

        -- Validate transfer amount --
        IF @Amount <= 0
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Transfer',
                                           'Non-positive amount',
                                           @FromAccountID;
            THROW 51003, 'Transfer amount must be greater than zero.', 1;
        END

        -- Check if balance is sufficient for transfer --
        SELECT @Balance = Balance FROM dbo.Account WHERE AccountID = @FromAccountID;
        IF @Balance < @Amount
        BEGIN
            EXEC Security.usp_LogRejection 'usp_Transfer',
                                           'Insufficient funds',
                                           @FromAccountID;
            THROW 51004, 'Insufficient funds for this transfer.', 1;
        END

        -- Begin transfer operation --
        BEGIN TRANSACTION;

            -- Reduce the balance of source account --
            UPDATE dbo.Account
            SET    Balance = Balance - @Amount
            WHERE  AccountID = @FromAccountID;

            -- Increase the balance of destination account --
            UPDATE dbo.Account
            SET    Balance = Balance + @Amount
            WHERE  AccountID = @ToAccountID;

            -- Record transaction into transaction record table --
            INSERT INTO dbo.TransactionRecord
                   (AccountID, Amount, TransactionType, ToAccountID, PerformedBy)
            VALUES (@FromAccountID, @Amount, 'Transfer', @ToAccountID, @Caller);

        COMMIT TRANSACTION;

        -- Output success message if successful --
        PRINT 'Transfer successful.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- Stored procedure for updating own staff record --
CREATE PROCEDURE dbo.usp_UpdateOwnStaffRecord
    @Phone  VARCHAR(20),
    @Branch VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @MyStaffID VARCHAR(6);

    -- Reject if the user is not a staff --
    IF IS_MEMBER('role_DBA')         <> 1
       AND IS_MEMBER('role_Manager') <> 1
       AND IS_MEMBER('role_Officer') <> 1
    BEGIN
        EXEC Security.usp_LogRejection 'usp_UpdateOwnStaffRecord',
                                       'Caller is not a member of any staff role',
                                       NULL;
        THROW 51009, 'Only staff members may update their own record.', 1;
    END

    -- Retrieve the staff ID of the user --
    SELECT @MyStaffID = m.StaffID
    FROM   Security.UserMapping AS m
    WHERE  m.DatabaseUser = USER_NAME();

    -- Reject if there is no staff ID --
    IF @MyStaffID IS NULL
    BEGIN
        EXEC Security.usp_LogRejection 'usp_UpdateOwnStaffRecord',
                                       'No staff record mapped to caller',
                                       NULL;
        THROW 51010, 'No staff record is mapped to your login.', 1;
    END

    -- Update record at Staff table (BEGIN TRANSACTION is not required coz this involves only one action) --
    UPDATE dbo.Staff
    SET    Phone  = @Phone,
           Branch = ISNULL(@Branch, Branch)
    WHERE  StaffID = @MyStaffID;

    -- Output success message once done --
    PRINT 'Your staff record has been updated.';
END;
GO

-- Stored procedure to update staff details (only for managers) --
CREATE PROCEDURE dbo.usp_UpdateStaffDetails
    @StaffID   VARCHAR(6),
    @StaffName VARCHAR(100) = NULL,
    @Position  VARCHAR(20)  = NULL,
    @Branch    VARCHAR(50)  = NULL,
    @Phone     VARCHAR(20)  = NULL,
    @Salary    DECIMAL(10,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @MyStaffID VARCHAR(6);

    -- Reject if user is not a manager --
    IF IS_MEMBER('role_Manager') <> 1
    BEGIN
        EXEC Security.usp_LogRejection 'usp_UpdateStaffDetails',
                                       'Caller is not a Bank Manager',
                                       @StaffID;
        THROW 51011, 'Only Bank Managers may manage staff details.', 1;
    END

    -- Check if the input staff ID is valid --
    IF NOT EXISTS (SELECT 1 FROM dbo.Staff WHERE StaffID = @StaffID)
    BEGIN
        EXEC Security.usp_LogRejection 'usp_UpdateStaffDetails',
                                       'Staff record not found',
                                       @StaffID;
        THROW 51012, 'Staff record not found.', 1;
    END

    -- Extract own ID --
    SELECT @MyStaffID = m.StaffID
    FROM   Security.UserMapping AS m
    WHERE  m.DatabaseUser = USER_NAME();

    -- Reject if the manager is attempting to update his own record --
    IF @MyStaffID = @StaffID
    BEGIN
        EXEC Security.usp_LogRejection 'usp_UpdateStaffDetails',
                                       'Manager attempted to update own staff record',
                                       @StaffID;
        THROW 51013, 'Managers may not update their own staff record. Use usp_UpdateOwnStaffRecord instead.', 1;
    END

    -- Update details except salary --
    UPDATE dbo.Staff
    SET    StaffName = ISNULL(@StaffName, StaffName),
           Position  = ISNULL(@Position,  Position),
           Branch    = ISNULL(@Branch,    Branch),
           Phone     = ISNULL(@Phone,     Phone)
    WHERE  StaffID = @StaffID;

    -- Salary is separated here so that this operation can rollback individually using trigger --
    IF @Salary IS NOT NULL
    BEGIN
        UPDATE dbo.Staff
        SET    Salary = @Salary
        WHERE  StaffID = @StaffID;
    END

    -- Return success message once done --
    PRINT 'Staff record updated.';
END;
GO

-- Stored procedure to create customer account --
CREATE PROCEDURE dbo.usp_CreateCustomerAccount
    @AccountID   VARCHAR(10),
    @CustomerID  VARCHAR(6),
    @AccountType VARCHAR(20),
    @OpeningBalance DECIMAL(12,2) = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Only officers can create new customer account --
    IF IS_MEMBER('role_Officer') <> 1
    BEGIN
        EXEC Security.usp_LogRejection 'usp_CreateCustomerAccount',
                                       'Caller is not a Bank Officer',
                                       @AccountID;
        THROW 51013, 'Only Bank Officers may manage customer accounts.', 1;
    END

    -- Check if the customer ID is valid --
    IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
    BEGIN
        EXEC Security.usp_LogRejection 'usp_CreateCustomerAccount',
                                       'Customer does not exist', 
                                       @CustomerID;
        THROW 51014, 'Customer does not exist.', 1;
    END

    -- Validate opening balance --
    IF @OpeningBalance < 0
    BEGIN
        EXEC Security.usp_LogRejection 'usp_CreateCustomerAccount',
                                       'Negative opening balance',
                                       @AccountID;
        THROW 51015, 'Opening balance cannot be negative.', 1;
    END

    -- Add account into the Account table --
    INSERT INTO dbo.Account (AccountID, CustomerID, AccountType, Balance)
    VALUES (@AccountID, @CustomerID, @AccountType, @OpeningBalance);

    -- Output success message once done --
    PRINT 'Customer account created.';
END;
GO

-- Stored procedure to update details of customer account --
CREATE PROCEDURE dbo.usp_UpdateCustomerAccount
    @AccountID   VARCHAR(10),
    @AccountType VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    -- Reject if user is not an officer --
    IF IS_MEMBER('role_Officer') <> 1
    BEGIN
        EXEC Security.usp_LogRejection 'usp_UpdateCustomerAccount',
                                       'Caller is not a Bank Officer',
                                       @AccountID;
        THROW 51013, 'Only Bank Officers may manage customer accounts.', 1;
    END

    -- Update account type based on account ID --
    UPDATE dbo.Account
    SET    AccountType = @AccountType
    WHERE  AccountID = @AccountID;

    -- If nothing changed, this means the account ID is invalid --
    IF @@ROWCOUNT = 0
    BEGIN
        EXEC Security.usp_LogRejection 'usp_UpdateCustomerAccount',
                                       'Account not found',
                                       @AccountID;
        THROW 51016, 'Account not found.', 1;
    END

    -- Show output message once done --
    PRINT 'Customer account updated.';
END;
GO

-- Grant and deny acccess to each SP based on authorisation matrix --
GRANT EXECUTE ON dbo.usp_Deposit  TO role_Customer;
GRANT EXECUTE ON dbo.usp_Withdraw TO role_Customer;
GRANT EXECUTE ON dbo.usp_Transfer TO role_Customer;
DENY  EXECUTE ON dbo.usp_Deposit  TO role_DBA, role_Manager, role_Officer;
DENY  EXECUTE ON dbo.usp_Withdraw TO role_DBA, role_Manager, role_Officer;
DENY  EXECUTE ON dbo.usp_Transfer TO role_DBA, role_Manager, role_Officer;

GRANT EXECUTE ON dbo.usp_UpdateOwnStaffRecord TO role_DBA, role_Manager, role_Officer;
DENY  EXECUTE ON dbo.usp_UpdateOwnStaffRecord TO role_Customer;
GRANT EXECUTE ON dbo.usp_UpdateStaffDetails   TO role_Manager;
DENY  EXECUTE ON dbo.usp_UpdateStaffDetails   TO role_DBA, role_Officer, role_Customer;

GRANT EXECUTE ON dbo.usp_CreateCustomerAccount TO role_Officer;
GRANT EXECUTE ON dbo.usp_UpdateCustomerAccount TO role_Officer;
DENY  EXECUTE ON dbo.usp_CreateCustomerAccount TO role_DBA, role_Manager, role_Customer;
DENY  EXECUTE ON dbo.usp_UpdateCustomerAccount TO role_DBA, role_Manager, role_Customer;
GO

-- Verification of the creation and access control of stored procedures --
SELECT  OBJECT_SCHEMA_NAME(p.major_id) AS SchemaName,
        OBJECT_NAME(p.major_id)        AS ProcedureName,
        dp.name                        AS RoleName,
        p.permission_name,
        p.state_desc                   AS GrantOrDeny
FROM    sys.database_permissions AS p
JOIN    sys.procedures AS pr        ON pr.object_id = p.major_id
JOIN    sys.database_principals AS dp ON dp.principal_id = p.grantee_principal_id
ORDER BY ProcedureName, RoleName;
GO

/* -- Run the code below if anything goes wrong --
USE SmartBankProd;
GO

REVOKE EXECUTE ON dbo.usp_Deposit  TO role_Customer;
REVOKE EXECUTE ON dbo.usp_Withdraw TO role_Customer;
REVOKE EXECUTE ON dbo.usp_Transfer TO role_Customer;
REVOKE EXECUTE ON dbo.usp_Deposit  TO role_DBA, role_Manager, role_Officer;
REVOKE EXECUTE ON dbo.usp_Withdraw TO role_DBA, role_Manager, role_Officer;
REVOKE EXECUTE ON dbo.usp_Transfer TO role_DBA, role_Manager, role_Officer;

REVOKE EXECUTE ON dbo.usp_UpdateOwnStaffRecord TO role_DBA, role_Manager, role_Officer;
REVOKE EXECUTE ON dbo.usp_UpdateOwnStaffRecord TO role_Customer;
REVOKE EXECUTE ON dbo.usp_UpdateStaffDetails   TO role_Manager;
REVOKE EXECUTE ON dbo.usp_UpdateStaffDetails   TO role_DBA, role_Officer, role_Customer;

REVOKE EXECUTE ON dbo.usp_CreateCustomerAccount TO role_Officer;
REVOKE EXECUTE ON dbo.usp_UpdateCustomerAccount TO role_Officer;
REVOKE EXECUTE ON dbo.usp_CreateCustomerAccount TO role_DBA, role_Manager, role_Customer;
REVOKE EXECUTE ON dbo.usp_UpdateCustomerAccount TO role_DBA, role_Manager, role_Customer;
GO

DROP PROCEDURE IF EXISTS dbo.usp_UpdateCustomerAccount;
DROP PROCEDURE IF EXISTS dbo.usp_CreateCustomerAccount;
DROP PROCEDURE IF EXISTS dbo.usp_UpdateStaffDetails;
DROP PROCEDURE IF EXISTS dbo.usp_UpdateOwnStaffRecord;
DROP PROCEDURE IF EXISTS dbo.usp_Transfer;
DROP PROCEDURE IF EXISTS dbo.usp_Withdraw;
DROP PROCEDURE IF EXISTS dbo.usp_Deposit;
DROP PROCEDURE IF EXISTS [Security].usp_LogRejection;
GO
*/
