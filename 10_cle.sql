
-- CLE for production DB --
USE SmartBankProd;
GO

-- Create the database master key for production DB (CLE) --
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'SmartBankProd#DMK@2026';
GO

-- If certificate is unavailable, create it --
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'Cert_CustomerPII')
    CREATE CERTIFICATE Cert_CustomerPII WITH SUBJECT = 'Certificate protecting the customer PII symmetric key';
GO

-- Backup certificate if there is no existing ones --
DECLARE @FileExists INT;
CREATE TABLE #FileCheck (FileExists INT, IsDirectory INT, ParentExists INT);
INSERT INTO #FileCheck EXEC master.dbo.xp_fileexist 'C:\SmartBankServer\Encryption\Cert_CustomerPII.cer';
SELECT @FileExists = FileExists FROM #FileCheck;

IF @FileExists = 0
    BACKUP CERTIFICATE Cert_CustomerPII
        TO FILE = 'C:\SmartBankServer\Encryption\Cert_CustomerPII.cer'
        WITH PRIVATE KEY (
            FILE = 'C:\SmartBankServer\Encryption\Cert_CustomerPII.pvk',
            ENCRYPTION BY PASSWORD = 'C3rtBackup#PII2026'
        );

DROP TABLE #FileCheck;
GO

-- Create encryption key for CLE --
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = 'SK_CustomerPII')
    CREATE SYMMETRIC KEY SK_CustomerPII
        WITH ALGORITHM = AES_256
        ENCRYPTION BY CERTIFICATE Cert_CustomerPII;
GO

-- Add the ICNumber_Enc column (make it nullable first coz it's empty initially) --
ALTER TABLE dbo.Customer ADD ICNumber_Enc VARBINARY(256) NULL;
GO

-- Migrate the values from ICNumber to ICNumber_Enc --
OPEN SYMMETRIC KEY SK_CustomerPII DECRYPTION BY CERTIFICATE Cert_CustomerPII;

UPDATE dbo.Customer
SET    ICNumber_Enc = ENCRYPTBYKEY(KEY_GUID('SK_CustomerPII'), ICNumber);

CLOSE SYMMETRIC KEY SK_CustomerPII;
GO

-- Validate that the IC numbers are transferred correctly before dropping old column --
OPEN SYMMETRIC KEY SK_CustomerPII DECRYPTION BY CERTIFICATE Cert_CustomerPII;

SELECT  CustomerID,
        ICNumber                                          AS Plaintext_BeforeDrop,
        ICNumber_Enc                                      AS Ciphertext,
        CONVERT(VARCHAR(20), DECRYPTBYKEY(ICNumber_Enc))  AS DecryptedBack
FROM    dbo.Customer;

CLOSE SYMMETRIC KEY SK_CustomerPII;
GO

-- Drop old IC column if everything looks good --
ALTER TABLE dbo.Customer DROP COLUMN ICNumber;
GO

-- Now convert the ICNumber_Enc to not null since all data is loaded --
ALTER TABLE dbo.Customer ALTER COLUMN ICNumber_Enc VARBINARY(256) NOT NULL;
GO

-- Grant the certificate and encryption key only to manager --
GRANT VIEW DEFINITION ON SYMMETRIC KEY::SK_CustomerPII TO role_Manager;
GRANT CONTROL         ON CERTIFICATE::Cert_CustomerPII TO role_Manager;
DENY VIEW DEFINITION ON SYMMETRIC KEY::SK_CustomerPII TO role_Officer, role_Customer, role_DBA;
DENY CONTROL         ON CERTIFICATE::Cert_CustomerPII TO role_Officer, role_Customer, role_DBA;
GO

-- View to retrieve customer details --
CREATE VIEW dbo.vw_CustomerIC
AS
    SELECT  CustomerID,
            CustomerName,
            CONVERT(VARCHAR(20), DECRYPTBYKEY(ICNumber_Enc)) AS ICNumber
    FROM    dbo.Customer;
GO

GRANT SELECT ON dbo.vw_CustomerIC TO role_Manager, role_Officer;
DENY  SELECT ON dbo.vw_CustomerIC TO role_DBA, role_Customer;
GO

-- Stored procedure to retrieve IC number of a specific customer --
CREATE PROCEDURE dbo.usp_GetCustomerIC
    @CustomerID VARCHAR(6)
AS
BEGIN
    SET NOCOUNT ON;

    -- Make sure that the user is a manager --
    IF IS_MEMBER('role_Manager') <> 1
    BEGIN
        EXEC Security.usp_LogRejection 'usp_GetCustomerIC',
                                       'Caller is not a Bank Manager',
                                       @CustomerID;
        THROW 51040, 'Only Bank Managers may retrieve a customer IC number.', 1;
    END

    -- Allow managers to retrieve customer information --
    OPEN SYMMETRIC KEY SK_CustomerPII DECRYPTION BY CERTIFICATE Cert_CustomerPII;

    SELECT  CustomerID,
            CustomerName,
            CONVERT(VARCHAR(20), DECRYPTBYKEY(ICNumber_Enc)) AS ICNumber
    FROM    dbo.Customer
    WHERE   CustomerID = @CustomerID;

    CLOSE SYMMETRIC KEY SK_CustomerPII;
END;
GO

GRANT EXECUTE ON dbo.usp_GetCustomerIC TO role_Manager;
DENY  EXECUTE ON dbo.usp_GetCustomerIC TO role_Officer, role_Customer, role_DBA;
GO

-- Stored procedure to register customer --
CREATE PROCEDURE dbo.usp_RegisterCustomer
    @CustomerID   VARCHAR(6),
    @CustomerName VARCHAR(100),
    @ICNumber     VARCHAR(20),
    @Phone        VARCHAR(20)  = NULL,
    @Address      VARCHAR(200) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Retrieve the user who calls the SP --
    DECLARE @Caller SYSNAME = ORIGINAL_LOGIN();

    -- Reject if the user is not an officer --
    IF IS_ROLEMEMBER('role_Officer', @Caller) <> 1
    BEGIN
        EXEC Security.usp_LogRejection 'usp_RegisterCustomer',
                                       'Caller is not a Bank Officer',
                                       @CustomerID;
        THROW 51013, 'Only Bank Officers may manage customer accounts.', 1;
    END

    -- Validate if customer has already exist in the system --
    IF EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
    BEGIN
        EXEC Security.usp_LogRejection 'usp_RegisterCustomer',
                                       'Customer already exists',
                                       @CustomerID;
        THROW 51041, 'That CustomerID is already registered.', 1;
    END
    
    -- Perform validation on IC number --
    IF @ICNumber NOT LIKE '[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]'
    BEGIN
        EXEC Security.usp_LogRejection 'usp_RegisterCustomer',
                                       'IC number failed format validation',
                                       @CustomerID;
        THROW 51042, 'IC number must be in the format YYMMDD-PB-###G.', 1;
    END

    -- If everything is okay, update the Customer table --
    OPEN SYMMETRIC KEY SK_CustomerPII DECRYPTION BY CERTIFICATE Cert_CustomerPII;

    INSERT INTO dbo.Customer (CustomerID, CustomerName, ICNumber_Enc, Phone, [Address])
    VALUES (@CustomerID,
            @CustomerName,
            ENCRYPTBYKEY(KEY_GUID('SK_CustomerPII'), @ICNumber),
            @Phone,
            @Address);

    CLOSE SYMMETRIC KEY SK_CustomerPII;

    -- Output results once done --
    PRINT 'Customer registered. IC number stored encrypted.';
END;
GO

-- Only officers can register customers --
GRANT EXECUTE ON dbo.usp_RegisterCustomer TO role_Officer;
DENY  EXECUTE ON dbo.usp_RegisterCustomer TO role_DBA, role_Manager, role_Customer;
GO

-- Validate that CLE works on different roles --
EXECUTE AS USER = 'ofc_lim';
    SELECT USER_NAME() AS TestedAs, * FROM dbo.vw_CustomerIC;
REVERT;
GO

EXECUTE AS USER = 'mgr_aisyah';
    OPEN SYMMETRIC KEY SK_CustomerPII DECRYPTION BY CERTIFICATE Cert_CustomerPII;
    SELECT USER_NAME() AS TestedAs, * FROM dbo.vw_CustomerIC;
    CLOSE SYMMETRIC KEY SK_CustomerPII;
REVERT;
GO

/* -- Run this if anything goes wrong during CLE setup --
-- NOTE: Certificate files must be removed manually from the directory

USE SmartBankProd;
GO

-- Restore the ICNumber column --
IF COL_LENGTH('dbo.Customer', 'ICNumber') IS NULL
    ALTER TABLE dbo.Customer ADD ICNumber VARCHAR(20) NULL;
GO

OPEN SYMMETRIC KEY SK_CustomerPII DECRYPTION BY CERTIFICATE Cert_CustomerPII;

UPDATE dbo.Customer
SET    ICNumber = CONVERT(VARCHAR(20), DECRYPTBYKEY(ICNumber_Enc));

CLOSE SYMMETRIC KEY SK_CustomerPII;
GO

-- Make sure that the IC numbers are restored before running the rest --
SELECT  CustomerID,
        ICNumber,
        CASE WHEN ICNumber IS NULL THEN 'FAIL - do not continue' ELSE 'OK' END AS DecryptCheck
FROM    dbo.Customer;
GO

-- Restore NOT NULL constraint --
ALTER TABLE dbo.Customer ALTER COLUMN ICNumber VARCHAR(20) NOT NULL;
GO

-- Remove the views, SP, and the ICNumber_Enc column --
DROP VIEW      IF EXISTS dbo.vw_CustomerIC;
DROP PROCEDURE IF EXISTS dbo.usp_GetCustomerIC;
DROP PROCEDURE IF EXISTS dbo.usp_RegisterCustomer;
GO

IF COL_LENGTH('dbo.Customer', 'ICNumber_Enc') IS NOT NULL
    ALTER TABLE dbo.Customer DROP COLUMN ICNumber_Enc;
GO

-- Remove the certificate, encryption key and DB master key --
IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = 'SK_CustomerPII')
    DROP SYMMETRIC KEY SK_CustomerPII;
GO
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'Cert_CustomerPII')
    DROP CERTIFICATE Cert_CustomerPII;
GO
IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    DROP MASTER KEY;
GO
*/
