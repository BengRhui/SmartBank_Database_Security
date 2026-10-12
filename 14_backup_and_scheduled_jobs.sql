
-- Backup for both production and analytics DB --
USE master;
GO

-- Check if SQL Server Agent is enabled --
SELECT servicename, status_desc, startup_type_desc
FROM sys.dm_server_services
WHERE servicename LIKE 'SQL Server Agent%';

-- Manual full backup on production DB --
BACKUP DATABASE SmartBankProd
    TO DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Full.bak'
    WITH INIT,
         NAME = 'SmartBankProd Full Backup',
         DESCRIPTION = 'Weekly full backup baseline',
         CHECKSUM, STATS = 10;
GO

-- Manual differential backup on production DB --
BACKUP DATABASE SmartBankProd
    TO DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Diff.bak'
    WITH DIFFERENTIAL, INIT,
         NAME = 'SmartBankProd Differential Backup',
         CHECKSUM, STATS = 10;
GO

-- Manual transactional log backup on production DB --
BACKUP LOG SmartBankProd
    TO DISK = 'C:\SmartBankServer\Backup\Production\SmartBankProd_Log.trn'
    WITH INIT,
         NAME = 'SmartBankProd Log Backup',
         CHECKSUM, STATS = 10;
GO

-- Manual full backup on analytics DB --
BACKUP DATABASE SmartBankAnalytics
    TO DISK = 'C:\SmartBankServer\Backup\Analytics\SmartBankAnalytics_Full.bak'
    WITH INIT, NAME = 'Analytics Full Backup', CHECKSUM, STATS = 10;
GO

-- Switch to msdb to set config --
USE msdb;
GO

/*====== Production - Full Weekly Backup (02:00 am) ======*/
-- Create job container --
EXEC msdb.dbo.sp_add_job
     @job_name = 'SmartBank - Full Backup (Weekly)',
     @description = 'Weekly full backup of SmartBankProd.',
     @notify_level_eventlog = 2;        -- write to Windows event log on failure

-- Define the backup step --
EXEC msdb.dbo.sp_add_jobstep
     @job_name  = 'SmartBank - Full Backup (Weekly)',
     @step_name = 'Full backup',
     @subsystem = 'TSQL',
     @database_name = 'master',
     @command = N'
     DECLARE @File NVARCHAR(300) = ''C:\SmartBankServer\Backup\Production\SmartBankProd_Full_'' +
                                   FORMAT(SYSDATETIME(), ''yyyyMMdd_HHmmss'') + ''.bak'';
     BACKUP DATABASE SmartBankProd TO DISK = @File
     WITH INIT, NAME = ''SmartBankProd Full'', CHECKSUM, STATS = 10;
     ';

-- Create schedule --
EXEC msdb.dbo.sp_add_schedule
     @schedule_name = 'SmartBank_Weekly_Sunday_0200',
     @freq_type = 8,                    -- weekly
     @freq_interval = 1,                -- Sunday
     @freq_recurrence_factor = 1,
     @active_start_time = 020000;

-- Attach schedule to job --
EXEC msdb.dbo.sp_attach_schedule
     @job_name = 'SmartBank - Full Backup (Weekly)',
     @schedule_name = 'SmartBank_Weekly_Sunday_0200';

-- Register job to server --
EXEC msdb.dbo.sp_add_jobserver @job_name = 'SmartBank - Full Backup (Weekly)';
GO

/*====== Production - Differential Daily Backup (03:00 am) ======*/
EXEC msdb.dbo.sp_add_job
     @job_name = 'SmartBank - Differential Backup (Daily)',
     @description = 'Daily differential backup of SmartBankProd.',
     @notify_level_eventlog = 2;

EXEC msdb.dbo.sp_add_jobstep
     @job_name  = 'SmartBank - Differential Backup (Daily)',
     @step_name = 'Differential backup',
     @subsystem = 'TSQL',
     @database_name = 'master',
     @command = N'
     DECLARE @File NVARCHAR(300) = ''C:\SmartBankServer\Backup\Production\SmartBankProd_Diff_'' +
                                   FORMAT(SYSDATETIME(), ''yyyyMMdd_HHmmss'') + ''.bak'';
     BACKUP DATABASE SmartBankProd TO DISK = @File
     WITH DIFFERENTIAL, INIT, NAME = ''SmartBankProd Differential'', CHECKSUM, STATS = 10;
     ';

EXEC msdb.dbo.sp_add_schedule
     @schedule_name = 'SmartBank_Daily_0300',
     @freq_type = 4,                    -- daily
     @freq_interval = 1,
     @active_start_time = 030000;

EXEC msdb.dbo.sp_attach_schedule
     @job_name = 'SmartBank - Differential Backup (Daily)',
     @schedule_name = 'SmartBank_Daily_0300';

EXEC msdb.dbo.sp_add_jobserver @job_name = 'SmartBank - Differential Backup (Daily)';
GO

/*====== Production - Transactional Log Daily Backup (15 minutes) ======*/
EXEC msdb.dbo.sp_add_job
     @job_name = 'SmartBank - Log Backup (15 min)',
     @description = 'Transaction log backup every 15 minutes. Delivers the 15-minute RPO.',
     @notify_level_eventlog = 2;

EXEC msdb.dbo.sp_add_jobstep
     @job_name  = 'SmartBank - Log Backup (15 min)',
     @step_name = 'Log backup',
     @subsystem = 'TSQL',
     @database_name = 'master',
     @command = N'
     DECLARE @File NVARCHAR(300) = ''C:\SmartBankServer\Backup\Production\SmartBankProd_Log_'' +
                                   FORMAT(SYSDATETIME(), ''yyyyMMdd_HHmmss'') + ''.trn'';
     BACKUP LOG SmartBankProd TO DISK = @File
     WITH INIT, NAME = ''SmartBankProd Log'', CHECKSUM, STATS = 10;
     ';

EXEC msdb.dbo.sp_add_schedule
     @schedule_name = 'SmartBank_Every_15_Minutes',
     @freq_type = 4,                    -- daily
     @freq_interval = 1,
     @freq_subday_type = 4,             -- minutes
     @freq_subday_interval = 15,
     @active_start_time = 000000,
     @active_end_time   = 235959;

EXEC msdb.dbo.sp_attach_schedule
     @job_name = 'SmartBank - Log Backup (15 min)',
     @schedule_name = 'SmartBank_Every_15_Minutes';

EXEC msdb.dbo.sp_add_jobserver @job_name = 'SmartBank - Log Backup (15 min)';
GO

/*====== Analytics - Full Weekly Backup (02:00 am) ======*/
EXEC msdb.dbo.sp_add_job
     @job_name = 'SmartBank - Analytics Backup (Weekly)',
     @description = 'Weekly full backup of SmartBankAnalytics. No log backups - SIMPLE recovery.',
     @notify_level_eventlog = 2;

EXEC msdb.dbo.sp_add_jobstep
     @job_name  = 'SmartBank - Analytics Backup (Weekly)',
     @step_name = 'Analytics full backup',
     @subsystem = 'TSQL',
     @database_name = 'master',
     @command = N'
     DECLARE @File NVARCHAR(300) = ''C:\SmartBankServer\Backup\Analytics\SmartBankAnalytics_Full_'' +
                                   FORMAT(SYSDATETIME(), ''yyyyMMdd_HHmmss'') + ''.bak'';
     BACKUP DATABASE SmartBankAnalytics TO DISK = @File
     WITH INIT, NAME = ''Analytics Full'', CHECKSUM, STATS = 10;';

EXEC msdb.dbo.sp_attach_schedule
     @job_name = 'SmartBank - Analytics Backup (Weekly)',
     @schedule_name = 'SmartBank_Weekly_Sunday_0200';

EXEC msdb.dbo.sp_add_jobserver @job_name = 'SmartBank - Analytics Backup (Weekly)';
GO

/*====== Additional: Analytics - Nightly ETL Job (01:00 am) ======*/
EXEC msdb.dbo.sp_add_job
     @job_name = 'SmartBank - Nightly Analytics ETL',
     @description = 'One-way load from SmartBankProd into SmartBankAnalytics with static masking and hashing.',
     @notify_level_eventlog = 2;

EXEC msdb.dbo.sp_add_jobstep
     @job_name   = 'SmartBank - Nightly Analytics ETL',
     @step_name  = 'Run ETL',
     @subsystem  = 'TSQL',
     @database_name = 'SmartBankAnalytics',
     @command    = N'EXEC Reporting.usp_RunETL;',
     @retry_attempts = 2,
     @retry_interval = 5;

EXEC msdb.dbo.sp_add_schedule
     @schedule_name = 'SmartBank_Nightly_0100',
     @freq_type     = 4,          -- daily
     @freq_interval = 1,
     @active_start_time = 010000; -- 01:00

EXEC msdb.dbo.sp_attach_schedule
     @job_name      = 'SmartBank - Nightly Analytics ETL',
     @schedule_name = 'SmartBank_Nightly_0100';

EXEC msdb.dbo.sp_add_jobserver
     @job_name = 'SmartBank - Nightly Analytics ETL';
GO

/*====== Additional: Backup Cleaning - Daily Job (04:00 am) ======*/
EXEC msdb.dbo.sp_add_job
     @job_name = 'SmartBank - Backup Retention Cleanup (Daily)',
     @description = 'Deletes backup files past their retention window',
     @notify_level_eventlog = 2;

EXEC msdb.dbo.sp_add_jobstep
     @job_name  = 'SmartBank - Backup Retention Cleanup (Daily)',
     @step_name = 'Delete expired backup files',
     @subsystem = 'TSQL',
     @database_name = 'master',
     @command = N'
     EXEC master.dbo.xp_delete_file 0, N''C:\SmartBankServer\Backup\Production'', N''bak'', DATEADD(DAY, -28, SYSDATETIME());
     EXEC master.dbo.xp_delete_file 0, N''C:\SmartBankServer\Backup\Production'', N''trn'', DATEADD(DAY,  -3, SYSDATETIME());
     EXEC master.dbo.xp_delete_file 0, N''C:\SmartBankServer\Backup\Analytics'',  N''bak'', DATEADD(DAY, -28, SYSDATETIME());
     ';

EXEC msdb.dbo.sp_add_schedule
     @schedule_name = 'SmartBank_Daily_0400',
     @freq_type = 4,                    -- daily
     @freq_interval = 1,
     @active_start_time = 040000;       -- after all backups complete

EXEC msdb.dbo.sp_attach_schedule
     @job_name = 'SmartBank - Backup Retention Cleanup (Daily)',
     @schedule_name = 'SmartBank_Daily_0400';

EXEC msdb.dbo.sp_add_jobserver @job_name = 'SmartBank - Backup Retention Cleanup (Daily)';
GO

-- Verify that job and schedule configuration is correct --
SELECT  j.name AS JobName,
        j.enabled,
        s.name AS ScheduleName,
        s.freq_type,
        s.freq_subday_interval,
        s.active_start_time
FROM    msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.sysjobschedules AS js ON js.job_id = j.job_id
LEFT JOIN msdb.dbo.sysschedules    AS s  ON s.schedule_id = js.schedule_id
WHERE   j.name LIKE 'SmartBank%'
ORDER BY j.name;
GO

-- Verify that backup was performed --
SELECT  bs.database_name,
        bs.backup_start_date,
        bs.backup_finish_date,
        CASE bs.type WHEN 'D' THEN 'Full'
                     WHEN 'I' THEN 'Differential'
                     WHEN 'L' THEN 'Transaction Log' END AS BackupType,
        CAST(bs.backup_size / 1048576.0 AS DECIMAL(10,2)) AS SizeMB,
        bmf.physical_device_name
FROM    msdb.dbo.backupset AS bs
JOIN    msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE   bs.database_name IN ('SmartBankProd','SmartBankAnalytics')
ORDER BY bs.backup_start_date DESC;
GO

/* -- Additional code: This is used to trigger backup immediately --
EXEC msdb.dbo.sp_start_job @job_name = 'SmartBank - Full Backup (Weekly)';
EXEC msdb.dbo.sp_start_job @job_name = 'SmartBank - Differential Backup (Daily)';
EXEC msdb.dbo.sp_start_job @job_name = 'SmartBank - Log Backup (15 min)';
EXEC msdb.dbo.sp_start_job @job_name = 'SmartBank - Analytics Backup (Weekly)';
*/

/* -- Run the code below if anything goes wrong --
Note: Please remove the backup files manually if you have to delete them.

USE msdb;
GO

-- Remove jobs --
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SmartBank - Full Backup (Weekly)')
    EXEC msdb.dbo.sp_delete_job @job_name = 'SmartBank - Full Backup (Weekly)',
                                @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SmartBank - Differential Backup (Daily)')
    EXEC msdb.dbo.sp_delete_job @job_name = 'SmartBank - Differential Backup (Daily)',
                                @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SmartBank - Log Backup (15 min)')
    EXEC msdb.dbo.sp_delete_job @job_name = 'SmartBank - Log Backup (15 min)',
                                @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SmartBank - Analytics Backup (Weekly)')
    EXEC msdb.dbo.sp_delete_job @job_name = 'SmartBank - Analytics Backup (Weekly)',
                                @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SmartBank - Nightly Analytics ETL')
    EXEC msdb.dbo.sp_delete_job @job_name = 'SmartBank - Nightly Analytics ETL',
                                @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SmartBank - Backup Retention Cleanup (Daily)')
    EXEC msdb.dbo.sp_delete_job @job_name = 'SmartBank - Backup Retention Cleanup (Daily)',
                                @delete_unused_schedule = 1;
GO

-- Remove schedules --
DECLARE @ScheduleID INT;
WHILE EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name LIKE 'SmartBank[_]%')
BEGIN
    SELECT TOP (1) @ScheduleID = schedule_id
    FROM   msdb.dbo.sysschedules
    WHERE  name LIKE 'SmartBank[_]%';
    EXEC msdb.dbo.sp_delete_schedule @schedule_id  = @ScheduleID,
                                     @force_delete = 1;
END
GO

-- Clear all backup history in msdb --
EXEC msdb.dbo.sp_delete_backuphistory @oldest_date = '9999-12-31';
GO

-- This confirms that everything is cleared --
SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE 'SmartBank%';
SELECT name FROM msdb.dbo.sysschedules WHERE name LIKE 'SmartBank%';
GO
*/
