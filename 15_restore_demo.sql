
-- NOTE: DO NOT RUN THIS FILE DIRECTLY! The STOPAT at line 88 must be changed before running restoration!

/*===== Prerequisite: Have to create baseline backup files to support restoration =====*/
USE master;
GO

-- Stop the service --
EXEC msdb.dbo.sp_update_job @job_name = 'SmartBank - Full Backup (Weekly)',        @enabled = 0;
EXEC msdb.dbo.sp_update_job @job_name = 'SmartBank - Differential Backup (Daily)', @enabled = 0;
EXEC msdb.dbo.sp_update_job @job_name = 'SmartBank - Log Backup (15 min)',         @enabled = 0;
GO

-- Create baseline full backup --
BACKUP DATABASE SmartBankProd
    TO DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Full.bak'
    WITH INIT, NAME = 'Baseline full', CHECKSUM, STATS = 10;
GO

-- Create baseline differential backup --
BACKUP DATABASE SmartBankProd
    TO DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Diff.bak'
    WITH DIFFERENTIAL, INIT, NAME = 'Baseline differential', CHECKSUM, STATS = 10;
GO

-- Create baseline transactional log backup --
BACKUP LOG SmartBankProd
    TO DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Log.trn'
    WITH INIT, NAME = 'Baseline log', CHECKSUM, STATS = 10;
GO
/*========================= PREREQUISITE ENDS HERE ==========================*/

-- Restoration demo for production DB --
USE SmartBankProd;
GO

-- Record a safe point in time before incident happens --
DECLARE @SafePointInTime DATETIME2(3) = SYSDATETIME();
SELECT @SafePointInTime AS SafePointInTime;

-- Show account details before modification --
SELECT AccountID, Balance FROM dbo.Account;

-- Simulate accident: all balances are accidentally set to 0 --
UPDATE dbo.Account SET Balance = 0;
SELECT AccountID, Balance FROM dbo.Account;
GO

-- Immediately stop all backup jobs --
EXEC msdb.dbo.sp_update_job @job_name = 'SmartBank - Full Backup (Weekly)',        @enabled = 0;
EXEC msdb.dbo.sp_update_job @job_name = 'SmartBank - Differential Backup (Daily)', @enabled = 0;
EXEC msdb.dbo.sp_update_job @job_name = 'SmartBank - Log Backup (15 min)',         @enabled = 0;
GO

-- Perform final backup (tail-log backup) --
BACKUP LOG SmartBankProd
    TO DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_TailLog.trn'
    WITH INIT, NAME = 'Tail log before recovery';
GO

-- Perform restoration to a recovery DB first --
USE master;
GO

-- Restore full backup --
RESTORE DATABASE SmartBankProd_Recovery
    FROM DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Full.bak'
    WITH MOVE 'SmartBankProd'     TO 'C:\SmartBankServer\Backup\Production\SmartBankProd_Recovery.mdf',
         MOVE 'SmartBankProd_log' TO 'C:\SmartBankServer\Backup\Production\SmartBankProd_Recovery.ldf',
         NORECOVERY, REPLACE, STATS = 10;
GO

-- Restore differential backup --
RESTORE DATABASE SmartBankProd_Recovery
    FROM DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Diff.bak'
    WITH NORECOVERY, STATS = 10;
GO

-- Restore transactional log backup --
RESTORE LOG SmartBankProd_Recovery
    FROM DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Log.trn'
    WITH NORECOVERY, STATS = 10;
GO

-- Restore tail-log backup, stopping just before the accidental modification --
RESTORE LOG SmartBankProd_Recovery
    FROM DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_TailLog.trn'
    WITH STOPAT = '2026-08-20 01:28:18.975', RECOVERY, STATS = 10;
GO

-- Verification: the balances are correct in the recovery DB --
SELECT AccountID, Balance FROM SmartBankProd_Recovery.dbo.Account;
GO

-- Reconcile affected tables back to production --
BEGIN TRANSACTION;

-- Account table --
UPDATE p
SET    p.Balance = r.Balance
FROM   SmartBankProd.dbo.Account AS p
JOIN   SmartBankProd_Recovery.dbo.Account AS r ON r.AccountID = p.AccountID;

-- Transaction record table --
UPDATE p
SET    p.Amount          = r.Amount,
       p.TransactionType = r.TransactionType,
       p.TransDate       = r.TransDate,
       p.ToAccountID     = r.ToAccountID
FROM   SmartBankProd.dbo.TransactionRecord AS p
JOIN   SmartBankProd_Recovery.dbo.TransactionRecord AS r ON r.TransID = p.TransID;

COMMIT TRANSACTION;
GO

-- Confirm production now matches the recovery copy --
SELECT AccountID, Balance FROM SmartBankProd.dbo.Account;
GO

-- Re-enable existing backup jobs once done --
EXEC msdb.dbo.sp_update_job @job_name = 'SmartBank - Full Backup (Weekly)',        @enabled = 1;
EXEC msdb.dbo.sp_update_job @job_name = 'SmartBank - Differential Backup (Daily)', @enabled = 1;
EXEC msdb.dbo.sp_update_job @job_name = 'SmartBank - Log Backup (15 min)',         @enabled = 1;
GO

SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name LIKE 'SmartBank%';
GO

-- Lightweight check to verify backup file integrity --
RESTORE VERIFYONLY FROM DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Full.bak';
GO

RESTORE HEADERONLY FROM DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Full.bak';
GO

-- Lastly, drop the recovery DB --
USE master;
GO

IF DB_ID('SmartBankProd_Recovery') IS NOT NULL
BEGIN
    ALTER DATABASE SmartBankProd_Recovery SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SmartBankProd_Recovery;
END
GO
