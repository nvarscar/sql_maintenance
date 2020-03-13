# define runtime settings
. .\settings.ps1
# define environments
$servers = 'localhost','localhost:14333'
# Or load them from your CMS! 
# $servers = Get-DbaRegisteredServerGroup

Install-DbaMaintenanceSolution -SqlInstance $servers -Database master -BackupLocation /backups -InstallJobs -ReplaceExisting -LogToTable