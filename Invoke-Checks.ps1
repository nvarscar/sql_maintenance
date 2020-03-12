# Requirements:
$mod = Get-Module dbachecks -ErrorAction SilentlyContinue
if (-not $mod) {
    Install-Module dbachecks -Force -Scope CurrentUser
}
$pack = Get-Package ReportUnit -ErrorAction SilentlyContinue
if (-not $pack) {
    Install-Package ReportUnit -Force -Scope CurrentUser
}

$sPassword = ConvertTo-SecureString $env:password -AsPlainText -Force
$cred = New-Object pscredential $env:login, $sPassword
$servers = 'localhost','localhost:14333'
$checks = 'Database'
# $checks = 'SuspectPage'
$xmlFile = Join-Path (Get-Location) '.\report.xml'
$reportFile = '.\result.html'
Invoke-DbcCheck -SqlInstance $servers -Checks $checks -SqlCredential $cred -OutputFormat NUnitXml -OutputFile $xmlFile
$reportUnit = Get-Package ReportUnit | Select-Object -ExpandProperty Source | Split-Path -Parent
& "$reportUnit\tools\ReportUnit.exe" $xmlFile $reportFile
