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