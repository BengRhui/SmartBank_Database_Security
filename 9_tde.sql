
-- Encryption for production and analytics DB --
USE master;
GO

-- Create the database master key for master DB (TDE) --
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'M@sterKey#SmartBank2026';
GO

-- If certificate is not there, create a new certificate for production DB (TDE) --
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'TDECert_Production')
    CREATE CERTIFICATE TDECert_Production WITH SUBJECT = 'TDE Certificate - SmartBankProd Production';
GO

-- If certificate is not there, create a new certificate for analytics DB (TDE) --
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'TDECert_Analytics')
    CREATE CERTIFICATE TDECert_Analytics WITH SUBJECT = 'TDE Certificate - SmartBankAnalytics';
GO

-- Backup certificates: Check if there is existing cert files for production DB --
DECLARE @FileExists INT;
CREATE TABLE #FileCheck (FileExists INT, IsDirectory INT, ParentExists INT);
INSERT INTO #FileCheck EXEC master.dbo.xp_fileexist 'C:\SmartBankServer\Encryption\TDECert_Production.cer';
SELECT @FileExists = FileExists FROM #FileCheck;

-- Backup the production certificate if file does not exist --
IF @FileExists = 0
    BACKUP CERTIFICATE TDECert_Production
        TO FILE = 'C:\SmartBankServer\Encryption\TDECert_Production.cer'
        WITH PRIVATE KEY (
            FILE = 'C:\SmartBankServer\Encryption\TDECert_Production.pvk',
            ENCRYPTION BY PASSWORD = 'C3rtBackup#Prod2026'
        );

-- Backup certificate: Check if there is existing cert files for analytics DB --
TRUNCATE TABLE #FileCheck;
INSERT INTO #FileCheck EXEC master.dbo.xp_fileexist 'C:\SmartBankServer\Encryption\TDECert_Analytics.cer';
SELECT @FileExists = FileExists FROM #FileCheck;

-- Backup the analytics certificate if file does not exist --
IF @FileExists = 0
    BACKUP CERTIFICATE TDECert_Analytics
        TO FILE = 'C:\SmartBankServer\Encryption\TDECert_Analytics.cer'
        WITH PRIVATE KEY (
            FILE = 'C:\SmartBankServer\Encryption\TDECert_Analytics.pvk',
            ENCRYPTION BY PASSWORD = 'C3rtBackup#Ana2026'
        );

-- Cleanup: The FileCheck table is temporarily used for checking only --
DROP TABLE #FileCheck;
GO

-- Perform TDE on production DB --
USE SmartBankProd;
GO

IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID())
    CREATE DATABASE ENCRYPTION KEY
        WITH ALGORITHM = AES_256
        ENCRYPTION BY SERVER CERTIFICATE TDECert_Production;
GO

ALTER DATABASE SmartBankProd SET ENCRYPTION ON;
GO

-- Perform TDE on analytics DB --
USE SmartBankAnalytics;
GO

IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID())
    CREATE DATABASE ENCRYPTION KEY
        WITH ALGORITHM = AES_256
        ENCRYPTION BY SERVER CERTIFICATE TDECert_Analytics;
GO

ALTER DATABASE SmartBankAnalytics SET ENCRYPTION ON;
GO

-- Verify if TDE encryption is enabled for each encryption --
USE master;
GO

SELECT  DB_NAME(dek.database_id) AS DatabaseName,
        dek.encryption_state,
        CASE dek.encryption_state
             WHEN 1 THEN 'Unencrypted'
             WHEN 2 THEN 'Encryption in progress'
             WHEN 3 THEN 'Encrypted'
             WHEN 4 THEN 'Key change in progress'
             WHEN 5 THEN 'Decryption in progress' 
        END AS StateDescription,
        dek.key_algorithm,
        dek.key_length,
        c.name AS CertificateUsed
FROM    sys.dm_database_encryption_keys AS dek
LEFT JOIN sys.certificates AS c ON c.thumbprint = dek.encryptor_thumbprint;
GO

/* -- Run this if anything goes wrong --
-- NOTE: This does not remove the encryption files in the directory. That must be removed manually.

-- Turn off TDE --
USE master;
GO
ALTER DATABASE SmartBankProd      SET ENCRYPTION OFF;
ALTER DATABASE SmartBankAnalytics SET ENCRYPTION OFF;
GO

-- Wait until decryption finishes --
WHILE EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys
              WHERE database_id IN (DB_ID('SmartBankProd'), DB_ID('SmartBankAnalytics'))
                AND encryption_state <> 1)
BEGIN
    WAITFOR DELAY '00:00:05';
END
GO

-- Drop the database encryption key --
USE SmartBankProd;
GO
IF EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID())
    DROP DATABASE ENCRYPTION KEY;
GO
USE SmartBankAnalytics;
GO
IF EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID())
    DROP DATABASE ENCRYPTION KEY;
GO

-- Drop the certificates --
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'TDECert_Production')
    DROP CERTIFICATE TDECert_Production;
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'TDECert_Analytics')
    DROP CERTIFICATE TDECert_Analytics;
GO

-- Drop the database master key --
IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    DROP MASTER KEY;
GO
*/
