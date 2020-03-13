$servers = 'localhost','localhost:14333'
foreach ($server in $servers) {
    Start-DbaAgentJob -SqlInstance $server -Job 'DatabaseBackup - USER_DATABASES - FULL' -Wait
}