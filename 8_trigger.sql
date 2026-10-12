
-- Triggers for production DB --
USE SmartBankProd;
GO

-- Trigger to control the update of salary --
CREATE TRIGGER dbo.trg_Staff_SalaryGuard
ON dbo.Staff
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Perform nothing if the update does not involve salary --
    IF NOT UPDATE(Salary)
        RETURN;

    -- Identify the user who called the trigger --
    DECLARE @Caller SYSNAME = ORIGINAL_LOGIN();

    -- Capture the affected row before any rollback discards the pseudo-table --
    DECLARE @Detail VARCHAR(500) = (SELECT TOP (1) 'StaffID: ' + i.StaffID FROM inserted AS i);

    -- Check "inserted": the rows that are modified, reject if row modified involves the user --
    IF EXISTS (
            SELECT 1
            FROM   inserted AS i
            JOIN   [Security].UserMapping AS m ON m.StaffID = i.StaffID
            WHERE  m.LoginName = @Caller
        )
    BEGIN
        ROLLBACK TRANSACTION;
        EXEC [Security].usp_LogRejection 'trg_Staff_SalaryGuard',
                                         'Attempted to modify own salary',
                                         @Detail;
        THROW 51020, 'Refused: you cannot modify your own salary.', 1;
    END

    -- Also check if the role is manager, only managers can edit salaries --
    IF NOT EXISTS (
        SELECT 1 FROM sys.database_role_members
        WHERE role_principal_id   = DATABASE_PRINCIPAL_ID('role_Manager')
          AND member_principal_id = DATABASE_PRINCIPAL_ID(@Caller)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        EXEC [Security].usp_LogRejection 'trg_Staff_SalaryGuard',
                                         'Non-manager attempted to modify a salary',
                                         @Detail;
        THROW 51021, 'Refused: only Bank Managers may modify salary.', 1;
    END
END;
GO

-- Trigger to disable delete on transaction records --
CREATE TRIGGER dbo.trg_Transaction_NoDelete
ON dbo.TransactionRecord
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Capture the affected row before the rollback --
    DECLARE @Detail VARCHAR(500) = (SELECT TOP (1) 'TransID: ' + CONVERT(VARCHAR(12), d.TransID) FROM deleted AS d);

    -- Perform rollback and record into audit log --
    ROLLBACK TRANSACTION;
    EXEC [Security].usp_LogRejection 'trg_Transaction_NoDelete',
                                     'Attempted deletion of a transaction record',
                                     @Detail;
    THROW 51030, 'Transaction records are append-only and cannot be deleted.', 1;
END;
GO

-- Verification that triggers are enabled --
SELECT  t.name  AS TableName,
        tr.name AS TriggerName,
        tr.is_disabled,
        tr.is_instead_of_trigger
FROM    sys.triggers AS tr
JOIN    sys.tables   AS t ON t.object_id = tr.parent_id
ORDER BY t.name, tr.name;
GO

-- Quick test: Even sysadmin cannot delete transaction records --
BEGIN TRY
    DELETE FROM dbo.TransactionRecord WHERE TransID = 1;
    SELECT 'FAILED - a transaction row was deleted' AS Result;
END TRY
BEGIN CATCH
    SELECT 'PASSED - ledger is append-only' AS Result, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

/* -- Run the code below if anything goes wrong --
USE SmartBankProd;
GO

DROP TRIGGER IF EXISTS dbo.trg_Transaction_NoDelete;
DROP TRIGGER IF EXISTS dbo.trg_Staff_SalaryGuard;
GO
*/
