
-- ETL pipeline for analytics DB --
USE SmartBankAnalytics;
GO

-- Stored procedure for running ETL --
CREATE PROCEDURE Reporting.usp_RunETL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Define salt and other variables here --
    DECLARE @Salt      NVARCHAR(64) = N'SmartBank$2026$AnalyticsSalt';
    DECLARE @RunID     INT;
    DECLARE @StartedOn DATETIME2(0) = SYSDATETIME();

    -- ETL starts, so record as log --
    INSERT INTO Reporting.ETLRunLog (StartedOn, RunStatus)
    VALUES (@StartedOn, 'Running');

    SET @RunID = SCOPE_IDENTITY();

    BEGIN TRY
        BEGIN TRANSACTION;

            -- Remove existing data in fact and dimension tables of analytics DB --
            DELETE FROM Reporting.FactTransaction;
            DELETE FROM Reporting.FactAccount;
            DELETE FROM Reporting.DimCustomer;

            -- Extract customer data from production and load to dimension table --
            -- Note: Static data masking is applied here on customer name --
            -- Note: Hashing is also applied on customer ID --
            INSERT INTO Reporting.DimCustomer (CustomerHash, MaskedName)
            SELECT
                CONVERT(CHAR(64), HASHBYTES('SHA2_256', @Salt + c.CustomerID), 2),
                LEFT(c.CustomerName, 1) + REPLICATE('*', 7)
            FROM   SmartBankProd.dbo.Customer AS c;

            -- Extract account data from production into fact Account table --
            -- Note: Hashing applied on account ID and customer ID --
            INSERT INTO Reporting.FactAccount
                   (AccountHash, CustomerHash, AccountType, Balance)
            SELECT
                CONVERT(CHAR(64), HASHBYTES('SHA2_256', @Salt + a.AccountID), 2),
                CONVERT(CHAR(64), HASHBYTES('SHA2_256', @Salt + a.CustomerID), 2),
                a.AccountType,
                a.Balance
            FROM   SmartBankProd.dbo.Account AS a;

            -- Extract transaction data from production into fact Transaction table --
            INSERT INTO Reporting.FactTransaction
                   (TransHash, AccountHash, TransDate, Amount, TransactionType)
            SELECT
                CONVERT(CHAR(64), HASHBYTES('SHA2_256', @Salt + CONVERT(VARCHAR(12), t.TransID)), 2),
                CONVERT(CHAR(64), HASHBYTES('SHA2_256', @Salt + t.AccountID), 2),
                t.TransDate,
                t.Amount,
                t.TransactionType
            FROM   SmartBankProd.dbo.TransactionRecord AS t;

        COMMIT TRANSACTION;

        -- Once done, write success log --
        UPDATE Reporting.ETLRunLog
        SET    CompletedOn     = SYSDATETIME(),
               CustomerRows    = (SELECT COUNT(*) FROM Reporting.DimCustomer),
               AccountRows     = (SELECT COUNT(*) FROM Reporting.FactAccount),
               TransactionRows = (SELECT COUNT(*) FROM Reporting.FactTransaction),
               RunStatus       = 'Success'
        WHERE  RunID = @RunID;
        PRINT 'ETL completed successfully.';
    END TRY
    BEGIN CATCH

        -- If any error occurs, rollback the entire transaction --
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        -- Also write fail status to the log and throw error --
        UPDATE Reporting.ETLRunLog
        SET    CompletedOn = SYSDATETIME(),
               RunStatus   = 'Failed',
               Message     = LEFT(ERROR_MESSAGE(), 500)
        WHERE  RunID = @RunID;
        THROW;
    END CATCH
END;
GO

-- The ETL pipeline can only be executed by the ETL service role --
GRANT EXECUTE ON Reporting.usp_RunETL TO role_ETL_Service;
DENY EXECUTE  ON Reporting.usp_RunETL TO role_Analyst_ReadOnly;
GO

-- View to check ETL status --
CREATE VIEW Reporting.vw_ETLHealth
AS
    SELECT  RunID, StartedOn, CompletedOn, RunStatus,
            CustomerRows, AccountRows, TransactionRows, Message
    FROM    Reporting.ETLRunLog;
GO

-- View to check aggregated account summary --
CREATE VIEW Reporting.vw_AccountSummary
AS
    SELECT  AccountType,
            COUNT(*)            AS AccountCount,
            SUM(Balance)        AS TotalBalance,
            AVG(Balance)        AS AverageBalance,
            MIN(Balance)        AS MinBalance,
            MAX(Balance)        AS MaxBalance
    FROM    Reporting.FactAccount
    GROUP BY AccountType;
GO

-- View to check the trend of transactions --
CREATE VIEW Reporting.vw_TransactionTrend
AS
    SELECT  YEAR(TransDate)     AS TransYear,
            MONTH(TransDate)    AS TransMonth,
            TransactionType,
            COUNT(*)            AS TransactionCount,
            SUM(Amount)         AS TotalAmount,
            AVG(Amount)         AS AverageAmount
    FROM    Reporting.FactTransaction
    GROUP BY YEAR(TransDate), MONTH(TransDate), TransactionType;
GO

-- View to check the transaction records of customers --
CREATE VIEW Reporting.vw_CustomerActivity
AS
    SELECT  a.CustomerHash,             -- pseudonymous, never a real ID
            COUNT(*)                            AS AccountsHeld,
            SUM(a.Balance)                      AS TotalBalance,
            SUM(ISNULL(t.TransactionCount, 0))  AS TransactionCount
    FROM    Reporting.FactAccount AS a
    LEFT JOIN (SELECT   AccountHash,
                        COUNT(*) AS TransactionCount
               FROM     Reporting.FactTransaction
               GROUP BY AccountHash) AS t
           ON t.AccountHash = a.AccountHash
    GROUP BY a.CustomerHash;
GO

-- Only analysts can access the views --
GRANT SELECT ON Reporting.vw_ETLHealth        TO role_Analyst_ReadOnly;
GRANT SELECT ON Reporting.vw_AccountSummary   TO role_Analyst_ReadOnly;
GRANT SELECT ON Reporting.vw_TransactionTrend TO role_Analyst_ReadOnly;
GRANT SELECT ON Reporting.vw_CustomerActivity TO role_Analyst_ReadOnly;

DENY SELECT  ON Reporting.vw_ETLHealth        TO role_ETL_Service;
DENY SELECT  ON Reporting.vw_AccountSummary   TO role_ETL_Service;
DENY SELECT  ON Reporting.vw_TransactionTrend TO role_ETL_Service;
DENY SELECT  ON Reporting.vw_CustomerActivity TO role_ETL_Service;
GO

-- Demo: Execute the entire ETL pipeline once --
EXEC Reporting.usp_RunETL;
GO

-- Show that customer name is statically masked --
SELECT CustomerHash, MaskedName, LoadedOn FROM Reporting.DimCustomer;
GO

-- Show that account ID and customer ID is hashed --
SELECT  a.AccountID   AS ProductionAccountID,
        a.CustomerID  AS ProductionCustomerID,
        CONVERT(CHAR(64), HASHBYTES('SHA2_256', N'SmartBank$2026$AnalyticsSalt' + a.AccountID),  2) AS AccountHash,
        CONVERT(CHAR(64), HASHBYTES('SHA2_256', N'SmartBank$2026$AnalyticsSalt' + a.CustomerID), 2) AS CustomerHash
FROM    SmartBankProd.dbo.Account AS a;

SELECT AccountHash, CustomerHash, AccountType, Balance FROM Reporting.FactAccount;
GO

-- Show that the number of row counts match with production DB --
SELECT  'Customer' AS Entity,
        (SELECT COUNT(*) FROM SmartBankProd.dbo.Customer)   AS ProductionRows,
        (SELECT COUNT(*) FROM Reporting.DimCustomer)        AS AnalyticsRows
UNION ALL
SELECT  'Account',
        (SELECT COUNT(*) FROM SmartBankProd.dbo.Account),
        (SELECT COUNT(*) FROM Reporting.FactAccount)
UNION ALL
SELECT  'Transaction',
        (SELECT COUNT(*) FROM SmartBankProd.dbo.TransactionRecord),
        (SELECT COUNT(*) FROM Reporting.FactTransaction);
GO

-- Display the status of ETL jobs --
SELECT * FROM Reporting.vw_ETLHealth ORDER BY RunID DESC;
GO

/* -- Run below if anything goes wrong --
USE SmartBankAnalytics;
GO

IF OBJECT_ID('Reporting.vw_CustomerActivity')  IS NOT NULL DROP VIEW Reporting.vw_CustomerActivity;
IF OBJECT_ID('Reporting.vw_TransactionTrend')  IS NOT NULL DROP VIEW Reporting.vw_TransactionTrend;
IF OBJECT_ID('Reporting.vw_AccountSummary')    IS NOT NULL DROP VIEW Reporting.vw_AccountSummary;
IF OBJECT_ID('Reporting.vw_ETLHealth')         IS NOT NULL DROP VIEW Reporting.vw_ETLHealth;
IF OBJECT_ID('Reporting.usp_RunETL')           IS NOT NULL DROP PROCEDURE Reporting.usp_RunETL;
GO
*/
