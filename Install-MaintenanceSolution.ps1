# define runtime settings
. .\settings.ps1
# define environments
$servers = 'localhost','localhost:14333'
# Or load them from your CMS! 
# $servers = Get-DbaRegisteredServerGroup -SqlInstance localhost

# clean up existing jobs
Get-DbaAgentJob -SqlInstance $servers -Category 'Database Maintenance' | Remove-DbaAgentJob

# install the solution
Install-DbaMaintenanceSolution -SqlInstance $servers -Database master -BackupLocation /backups/sql -InstallJobs -ReplaceExisting -LogToTable