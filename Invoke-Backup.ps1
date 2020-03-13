# define runtime settings
. .\settings.ps1
# define environments
$servers = @{
    test = 'localhost','localhost:14333'
    production = 'localhost:14333','localhost'
}
# initiate backups for a specific environment
foreach ($server in $servers[$env:environment]) {
    Start-DbaAgentJob -SqlInstance $server -Job 'DatabaseBackup - USER_DATABASES - FULL' -Wait
}