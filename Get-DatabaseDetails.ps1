$sPassword = 'dbatools.IO' | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object pscredential 'sqladmin', $sPassword

$query = @'
SELECT * FROM master.sys.databases
'@

$servers = 'localhost','localhost:14333'
foreach ($server in $servers) {
    Invoke-DbaQuery -SqlInstance $server -SqlCredential $credential -Query $query
}



# foreach ($server in $servers) {
#     $data = Invoke-DbaQuery -SqlInstance $server -SqlCredential $credential -Query $query -AppendServerInstance -As PSObject
#     $data | Write-DbaDbTableData -SqlInstance localhost -SqlCredential $credential -AutoCreateTable -Table master.dbo.dbdetails
# }