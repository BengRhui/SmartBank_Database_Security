
-- Dynamic data masking on production DB --
USE SmartBankProd;
GO

-- DDM on phone number --
ALTER TABLE dbo.Customer
    ALTER COLUMN Phone ADD MASKED 
    WITH (FUNCTION = 'partial(3,"XXXXXX",2)');
GO

-- DDM on address --
ALTER TABLE dbo.Customer
    ALTER COLUMN [Address] ADD MASKED
    WITH (FUNCTION = 'default()');
GO

-- Granting UNMASK only to managers, others should not have the privilege to view --
GRANT UNMASK TO role_Manager;
DENY  UNMASK TO role_Officer;
DENY  UNMASK TO role_Customer;
DENY  UNMASK TO role_DBA;
GO

-- Verify that DDM is applied on the correct column --
SELECT  OBJECT_SCHEMA_NAME(c.object_id) AS SchemaName,
        OBJECT_NAME(c.object_id)        AS TableName,
        c.name                          AS ColumnName,
        c.masking_function              AS MaskFunction
FROM    sys.masked_columns AS c
ORDER BY TableName, ColumnName;
GO

-- Verify that unmask is granted to the correct user --
SELECT  dp.name AS RoleName, p.permission_name, p.state_desc AS GrantOrDeny
FROM    sys.database_permissions AS p
JOIN    sys.database_principals AS dp ON dp.principal_id = p.grantee_principal_id
WHERE   p.permission_name = 'UNMASK'
ORDER BY dp.name;
GO

-- Validate that DDM works on different roles --
EXECUTE AS USER = 'ofc_lim';
    SELECT USER_NAME() AS RunningAs, CustomerID, CustomerName, Phone, [Address]
    FROM   dbo.vw_CustomerProfile;
REVERT;
GO

EXECUTE AS USER = 'mgr_aisyah';
    SELECT USER_NAME() AS RunningAs, CustomerID, CustomerName, Phone, [Address]
    FROM   dbo.vw_CustomerProfile;
REVERT;
GO

/* -- Run below if anything goes wrong in this file --
USE SmartBankProd;
GO

IF EXISTS (SELECT 1 FROM sys.masked_columns
           WHERE object_id = OBJECT_ID('dbo.Customer') AND name = 'Phone')
    ALTER TABLE dbo.Customer ALTER COLUMN Phone DROP MASKED;

IF EXISTS (SELECT 1 FROM sys.masked_columns
           WHERE object_id = OBJECT_ID('dbo.Customer') AND name = 'Address')
    ALTER TABLE dbo.Customer ALTER COLUMN [Address] DROP MASKED;
GO

REVOKE UNMASK FROM role_Manager;
REVOKE UNMASK FROM role_Officer;
REVOKE UNMASK FROM role_Customer;
REVOKE UNMASK FROM role_DBA;
GO
*/
