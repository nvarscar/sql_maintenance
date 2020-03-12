# set passwords from environment vars
$sPassword = ConvertTo-SecureString $env:password -AsPlainText -Force
$cred = New-Object pscredential $env:login, $sPassword
$PSDefaultParameterValues = @{
    Disabled               = $false
    "*-Dba*:SqlCredential" = $cred
    "*-Dba*:SourceSqlCredential" = $cred
    "*-Dba*:DestinationSqlCredential" = $cred
    "*-Dba*:EnableException" = $true
}
$p = @{
    SqlInstance = $env:TargetServer
    Database = $env:TargetDatabase
}
if ($env:ToDate) {
    $p += @{ RestoreTime = $env:ToDate}
}

Get-DbaBackupHistory -SqlInstance $env:SourceServer -Database $env:SourceDatabase | Restore-DbaDatabase @p -WithReplace -ReplaceDbNameInFile -TrustDbBackupHistory