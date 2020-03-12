# Requirements:
if (-not (Get-Module dbachecks -ErrorAction SilentlyContinue)) {
    Install-Module dbachecks -SkipPublisherCheck -Confirm:$false -Scope CurrentUser
}
if (-not (Get-Package ReportUnit -ErrorAction SilentlyContinue)) {
    Install-Package ReportUnit -SkipPublisherCheck -Confirm:$false -Scope CurrentUser
}

. .\settings.ps1
$servers = 'localhost','localhost:14333'
$checks = 'Database'
# $checks = 'SuspectPage'
$xmlFile = Join-Path (Get-Location) '.\report.xml'
$reportFile = '.\result.html'
Invoke-DbcCheck -SqlInstance $servers -Checks $checks -SqlCredential $cred -OutputFormat NUnitXml -OutputFile $xmlFile
$reportUnit = Get-Package ReportUnit | Select-Object -ExpandProperty Source | Split-Path -Parent
& "$reportUnit\tools\ReportUnit.exe" $xmlFile $reportFile
