# Requirements:
# Install-Module dbachecks
# Install-Package ReportUnit

. .\settings.ps1
$servers = 'localhost','localhost:14333'
$cred.username
$checks = 'Database'
# $checks = 'SuspectPage'
$xmlFile = Join-Path (Get-Location) '.\report.xml'
$reportFile = '.\result.html'
Invoke-DbcCheck -SqlInstance $servers -Checks $checks -SqlCredential $cred -OutputFormat NUnitXml -OutputFile $xmlFile
$reportUnit = Get-Package ReportUnit | Select-Object -ExpandProperty Source | Split-Path -Parent
& "$reportUnit\tools\ReportUnit.exe" $xmlFile $reportFile
