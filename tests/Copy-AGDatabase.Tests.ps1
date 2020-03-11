Param (
	$SqlInstance = 'wpg1lsds02,7221',
    $SqlInstance2 = 'wpg1lsds02,7220'
)
if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }


$src = 'lab-sds-ag1,7221'
$tgt = 'wpg1lsds03,7221', 'wpg1lsds04,7221'
$tgtListener = 'lab-sds-ag1,7221'
$currentDate = Get-Date
$dateString = [string]$currentDate.Year + ([string]$currentDate.Month).PadLeft(2, '0') + ([string]$currentDate.Day).PadLeft(2, '0') + ([string]$currentDate.Hour).PadLeft(2, '0') + ([string]$currentDate.Minute).PadLeft(2, '0') + ([string]$currentDate.Second).PadLeft(2, '0')
$srcDb = "AG_Test_Src_$dateString"
$tgtDb = "AG_Test_Tgt_$dateString"
$agName = 'AG1'
$backupLocation = '\\wpg1dd02\np_SqlBackup\ADHOC\CopyMeTender_cdt.bak'

$sqlDropDb = @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '{0}') 
BEGIN 
    IF EXISTS (SELECT * FROM sys.databases WHERE name = '{0}' AND state_desc = 'ONLINE') 
        ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
    DROP DATABASE [{0}]
END
"@
$sqlGrants = @"
DECLARE @self sysname = 'dummy'
SELECT @self
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = @self)
    EXEC ('CREATE USER [' + @self + '] WITHOUT LOGIN')
EXEC sys.sp_addrolemember @rolename = 'db_datareader',  -- sysname
                          @membername = @self -- sysname
EXEC ('GRANT EXEC TO [' + @self + ']')
EXEC ('GRANT SELECT ON SCHEMA::dbo TO [' + @self + ']')
"@
$sqlCreateDb = "CREATE DATABASE [{0}]"
$sqlCreateTable = "CREATE TABLE cdt_test (a int)"
$sqlRenameDb = "EXEC sp_renamedb '{0}', '{1}'"
$psDropAgDb = {
	Param (
		[string]$SqlInstance,
		[string]$Database
	)
	$srv = Connect-DbaInstance -SqlInstance $SqlInstance
	if ($ag = $srv.Databases[$Database].AvailabilityGroupName) {
		if ($srv.AvailabilityGroups[$ag].LocalReplicaRole -eq 'Primary') {
			$srv.AvailabilityGroups[$ag].AvailabilityDatabases[$Database].Drop()
		}
	}
}
Describe "Copy-Database tests" {
	Context "Running backup-restores" {
		BeforeEach {
			Invoke-Command -ScriptBlock $psDropAgDb -ArgumentList ($src, $srcDb)
			$tgt | % { Invoke-Command -ScriptBlock $psDropAgDb -ArgumentList ($_, $tgtDb) }
			$null = Remove-DbaDatabase -SqlInstance $src -Database $srcDb -Confirm:$false
			$tgt | % { $null = Remove-DbaDatabase -Database $tgtDb -Confirm:$false -SqlInstance $_ }
			$null = Invoke-DbaSqlQuery -Query ($sqlCreateDb -f $srcDb) -SqlInstance $src
			$null = Invoke-DbaSqlQuery -Query $sqlCreateTable -SqlInstance $src -Database $srcDb
		}
		AfterAll {
			Invoke-Command -ScriptBlock $psDropAgDb -ArgumentList ($src, $srcDb)
			$tgt | % { Invoke-Command -ScriptBlock $psDropAgDb -ArgumentList ($_, $tgtDb) }
			$null = Remove-DbaDatabase -SqlInstance $src -Database $srcDb -Confirm:$false
			$tgt | % { $null = Remove-DbaDatabase -Database $tgtDb -Confirm:$false -SqlInstance $_ }
		}
		It "Restores a SIMPLE database on a AG cluster" {
			& $here\..\Copy-AGDatabase.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -AvailabilityGroup $agName -BackupFileLocation $backupLocation
			$dbs = @()
			$dbs += $tgt | % { (Connect-DbaInstance -SqlInstance $_).Databases[$tgtDb] }
			$sdb = (Connect-DbaInstance -SqlInstance $src).Databases[$srcDb]
			foreach ($db in $dbs) {
				$db.Name | Should Be $tgtDb
				$db.CreateDate | Should BeGreaterOrEqual (Get-Date).AddMinutes(-1)
				if ($db.Parent.AvailabilityGroups[$agName].LocalReplicaRole -eq 'Primary') {
					$db.IsAccessible | Should Be $true
					$db.Status | Should Be 'Normal'
					$db.Tables[0].Name | Should Be 'cdt_test'
				}
				$db.FileGroups.Files.FileName | % { $_.Split('\')[-1] } | Should Be ( $sdb.FileGroups.Files.FileName | % { $_.Split('\')[-1] -replace $srcDb, $tgtDb } ) 
				$db.LogFiles.FileName | % { $_.Split('\')[-1] } | Should Be ( $sdb.LogFiles.FileName | % { $_.Split('\')[-1] -replace $srcDb, $tgtDb } ) 
				$db.Owner | Should Be 'SQLSamurai'
			}
		}
		It "Restores a FULL database on a AG cluster" {
			$null = Set-DbaDbRecoveryModel -SqlInstance $src -Database $srcDb -RecoveryModel Full -Confirm:$false
			& $here\..\Copy-AGDatabase.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -AvailabilityGroup $agName -BackupFileLocation $backupLocation
			$dbs = @()
			$dbs += $tgt | % { (Connect-DbaInstance -SqlInstance $_).Databases[$tgtDb] }
			$sdb = (Connect-DbaInstance -SqlInstance $src).Databases[$srcDb]
			foreach ($db in $dbs) {
				$db.Name | Should Be $tgtDb
				$db.CreateDate | Should BeGreaterOrEqual (Get-Date).AddMinutes(-1)
				if ($db.Parent.AvailabilityGroups[$agName].LocalReplicaRole -eq 'Primary') {
					$db.IsAccessible | Should Be $true
					$db.Status | Should Be 'Normal'
					$db.Tables[0].Name | Should Be 'cdt_test'
				}
				$db.FileGroups.Files.FileName | % { $_.Split('\')[-1] } | Should Be ( $sdb.FileGroups.Files.FileName | % { $_.Split('\')[-1] -replace $srcDb, $tgtDb } ) 
				$db.LogFiles.FileName | % { $_.Split('\')[-1] } | Should Be ( $sdb.LogFiles.FileName | % { $_.Split('\')[-1] -replace $srcDb, $tgtDb } ) 
				$db.Owner | Should Be 'SQLSamurai'
			}
		}
		It "Overwrites an existing database and keeps permissions" {
			$null = Set-DbaDbRecoveryModel -SqlInstance $src -Database $srcDb -RecoveryModel Full -Confirm:$false
			& $here\..\Copy-AGDatabase.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -AvailabilityGroup $agName -BackupFileLocation $backupLocation
			$null = Invoke-DbaSqlQuery -Query $sqlGrants -SqlInstance $tgtListener -Database $tgtDb
			$perms = Export-DbaUser -SqlInstance $tgtListener -Database $tgtDb -User dummy -ExcludeGoBatchSeparator -DestinationVersion SqlServer2008/2008R2
			& $here\..\Copy-AGDatabase.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -BackupFileLocation $backupLocation -KeepPermissions -AvailabilityGroup $agName
			$after_perms = Export-DbaUser -SqlInstance $tgtListener -Database $tgtDb -User dummy -ExcludeGoBatchSeparator -DestinationVersion SqlServer2008/2008R2
			$after_perms | Should Be $perms
		}
		It "Restores the database and drops all the users" {
			$null = Invoke-DbaSqlQuery -Query $sqlGrants -SqlInstance $src -Database $srcDb
			$null = Set-DbaDbRecoveryModel -SqlInstance $src -Database $srcDb -RecoveryModel Full -Confirm:$false
			& $here\..\Copy-AGDatabase.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -AvailabilityGroup $agName -BackupFileLocation $backupLocation -DropUsers
			$after_perms = Export-DbaUser -SqlInstance $tgtListener -Database $tgtDb -User dummy -ExcludeGoBatchSeparator
			$after_perms | Should BeNullOrEmpty
		}
	}
}