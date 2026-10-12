
/* -- Note before running this query --
Under normal circumstances, how SSMS and SQL server communicate is by Shared Memory, not over a network.
Therefore, to show that encryption in transit takes place, we have to first switch our connection to TCP.
This can be done by opening PowerShell and run this command (change the server name accordingly):

$instancePath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL17.SMARTBANKSERVER\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
Get-ItemProperty -Path $instancePath -Name TcpPort, TcpDynamicPorts

Then, based on the TCP port, change the server name to:
tcp:localhost,<TCP_Port>

Once connection is established, the following query can be executed.
Make sure that net_transport = TCP to confirm that the current connection is TCP.
*/

-- Verify that connection is encrypted by default --
SELECT  c.session_id,
        s.login_name,
        c.encrypt_option,
        c.auth_scheme,
        c.net_transport
FROM    sys.dm_exec_connections AS c
JOIN    sys.dm_exec_sessions    AS s ON s.session_id = c.session_id
WHERE   s.is_user_process = 1 AND auth_scheme = 'SQL';
GO
