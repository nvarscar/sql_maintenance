Param (
    $SqlInstance = 'wpg1lsds02,7221',
    $SqlInstance2 = 'wpg1lsds02,7220'
)
if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }


$src = $SqlInstance
$tgt = $SqlInstance2
$currentDate = Get-Date
$dateString = [string]$currentDate.Year + ([string]$currentDate.Month).PadLeft(2, '0') + ([string]$currentDate.Day).PadLeft(2, '0') + ([string]$currentDate.Hour).PadLeft(2, '0') + ([string]$currentDate.Minute).PadLeft(2, '0') + ([string]$currentDate.Second).PadLeft(2, '0')
$srcDb = "Copy_Test_Src_$dateString"
$tgtDb = "Copy_Test_Tgt_$dateString"
$backupLocation = '\\wpg1dd02\np_SqlBackup\ADHOC\CopyMeTender_cdt.bak'

$sqlDropDb = @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '{0}') 
BEGIN 
    IF EXISTS (SELECT * FROM sys.databases WHERE name = '{0}' AND state_desc = 'ONLINE') 
        ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
    DROP DATABASE [{0}]
END
"@
$sqlCreateDb = "CREATE DATABASE [{0}]"
$sqlCreateTable = "CREATE TABLE cdt_test (a int)"
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
$sqlRenameDb = "EXEC sp_renamedb '{0}', '{1}'"
Describe "Copy-Database tests" {
    Context "Regular backup-restore" {
        BeforeEach {
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $src
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $src
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $tgt
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $tgt
            $null = Invoke-DbaSqlQuery -Query ($sqlCreateDb -f $srcDb) -SqlInstance $src
            $null = Invoke-DbaSqlQuery -Query $sqlCreateTable -SqlInstance $src -Database $srcDb
        }
        AfterAll {
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $src
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $src
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $tgt
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $tgt
        }
        It "Restores the database within the same server" {
            & $here\..\Copy-Database.ps1 -SourceServer $src -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -BackupFileLocation $backupLocation
            $db = (Connect-DbaInstance -SqlInstance $src).Databases[$tgtDb]
            $sdb = (Connect-DbaInstance -SqlInstance $src).Databases[$srcDb]
            $db.Name | Should Be $tgtDb
            $db.CreateDate | Should BeGreaterOrEqual (Get-Date).AddMinutes(-1)
            $db.IsAccessible | Should Be $true
            $db.Status | Should Be 'Normal'
            $db.FileGroups.Files.FileName | Should Be ( $sdb.FileGroups.Files.FileName | % { $_ -replace $srcDb, $tgtDb } ) 
            $db.LogFiles.FileName | Should Be ( $sdb.LogFiles.FileName | % { $_ -replace $srcDb, $tgtDb } ) 
            $db.Tables[0].Name | Should Be 'cdt_test'
            $db.Owner | Should Be 'SQLSamurai'
        }
        It "Restores the database on a different server" {
            & $here\..\Copy-Database.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -BackupFileLocation $backupLocation
            $db = (Connect-DbaInstance -SqlInstance $tgt).Databases[$tgtDb]
            $sdb = (Connect-DbaInstance -SqlInstance $src).Databases[$srcDb]
            $db.Name | Should Be $tgtDb
            $db.CreateDate | Should BeGreaterOrEqual (Get-Date).AddMinutes(-1)
            $db.IsAccessible | Should Be $true
            $db.Status | Should Be 'Normal'
            $db.FileGroups.Files.FileName | % { $_.Split('\')[-1] } | Should Be ( $sdb.FileGroups.Files.FileName | % { $_.Split('\')[-1] -replace $srcDb, $tgtDb } ) 
            $db.LogFiles.FileName | % { $_.Split('\')[-1] } | Should Be ( $sdb.LogFiles.FileName | % { $_.Split('\')[-1] -replace $srcDb, $tgtDb } ) 
            $db.Tables[0].Name | Should Be 'cdt_test'
            $db.Owner | Should Be 'SQLSamurai'
        }
        It "Overwrites an existing database and keeps permissions" {
            $null = Invoke-DbaSqlQuery -Query ($sqlCreateDb -f $tgtDb) -SqlInstance $tgt
            $null = Invoke-DbaSqlQuery -Query $sqlGrants -SqlInstance $tgt -Database $tgtDb
            $perms = Export-DbaUser -SqlInstance $tgt -Database $tgtDb -User dummy -ExcludeGoBatchSeparator -DestinationVersion SqlServer2008/2008R2
            & $here\..\Copy-Database.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -BackupFileLocation $backupLocation -KeepPermissions
            $db = (Connect-DbaInstance -SqlInstance $tgt).Databases[$tgtDb]
            $sdb = (Connect-DbaInstance -SqlInstance $src).Databases[$srcDb]
            $db.Name | Should Be $tgtDb
            $db.CreateDate | Should BeGreaterOrEqual (Get-Date).AddMinutes(-1)
            $db.IsAccessible | Should Be $true
            $db.Status | Should Be 'Normal'
            $db.FileGroups.Files.FileName | % { $_.Split('\')[-1] } | Should Be ( $sdb.FileGroups.Files.FileName | % { $_.Split('\')[-1] -replace $srcDb, $tgtDb } ) 
            $db.LogFiles.FileName | % { $_.Split('\')[-1] } | Should Be ( $sdb.LogFiles.FileName | % { $_.Split('\')[-1] -replace $srcDb, $tgtDb } ) 
            $db.Tables[0].Name | Should Be 'cdt_test'
            $db.Owner | Should Be 'SQLSamurai'
            $after_perms = Export-DbaUser -SqlInstance $tgt -Database $tgtDb -User dummy -ExcludeGoBatchSeparator -DestinationVersion SqlServer2008/2008R2
            $after_perms | Should Be $perms
        }
        It "Restores the database and drops all the users" {
            $null = Invoke-DbaSqlQuery -Query $sqlGrants -SqlInstance $src -Database $srcDb
            & $here\..\Copy-Database.ps1 -SourceServer $src -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -BackupFileLocation $backupLocation -DropUsers
            $db = (Connect-DbaInstance -SqlInstance $src).Databases[$tgtDb]
            $sdb = (Connect-DbaInstance -SqlInstance $src).Databases[$srcDb]
            $db.Name | Should Be $tgtDb
            $db.CreateDate | Should BeGreaterOrEqual (Get-Date).AddMinutes(-1)
            $db.IsAccessible | Should Be $true
            $db.Status | Should Be 'Normal'
            $db.FileGroups.Files.FileName | Should Be ( $sdb.FileGroups.Files.FileName | % { $_ -replace $srcDb, $tgtDb } ) 
            $db.LogFiles.FileName | Should Be ( $sdb.LogFiles.FileName | % { $_ -replace $srcDb, $tgtDb } ) 
            $db.Tables[0].Name | Should Be 'cdt_test'
            $db.Owner | Should Be 'SQLSamurai'
            $after_perms = Export-DbaUser -SqlInstance $src -Database $tgtDb -User dummy -ExcludeGoBatchSeparator
            $after_perms | Should BeNullOrEmpty
        }
    }
    Context "Negative backup-restore tests" {
        BeforeEach {
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $src
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $src
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $tgt
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $tgt
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f ("$tgtDb" + "_copy")) -SqlInstance $tgt
            $null = Invoke-DbaSqlQuery -Query ($sqlCreateDb -f $srcDb) -SqlInstance $src
            $null = Invoke-DbaSqlQuery -Query $sqlCreateTable -SqlInstance $src -Database $srcDb
        }
        AfterAll {
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $src
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $tgt
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $tgt
            $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f ("$tgtDb" + "_copy")) -SqlInstance $tgt
        }
        It "throws when backup path is unavailable" {
            { & $here\..\Copy-Database.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -BackupFileLocation "\\localhost\somenone\existent\path.bak" 3>$null } | Should Throw    
        }
        It "throws when source server is unavailable" {
            { & $here\..\Copy-Database.ps1 -SourceServer 'localhost,12345' -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -BackupFileLocation $backupLocation } | Should Throw    
        }
        It "throws when target server is unavailable" {
            { & $here\..\Copy-Database.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetServer NonExistingServer -TargetDatabaseName $tgtDb -BackupFileLocation $backupLocation } | Should Throw    
        }
        It "throws when source database is unavailable" {
            { & $here\..\Copy-Database.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName NonExistingDatabase -TargetDatabaseName $tgtDb -BackupFileLocation $backupLocation } | Should Throw    
        }
        It "throws when restore encounters an error - filename already used" {
            $null = Invoke-DbaSqlQuery -Query ($sqlCreateDb -f $tgtDb) -SqlInstance $tgt -EnableException
            $null = Invoke-DbaSqlQuery -Query ($sqlRenameDb -f @($tgtDb, ("$tgtDb" + "_copy"))) -SqlInstance $tgt -EnableException
            { & $here\..\Copy-Database.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -BackupFileLocation $backupLocation } | Should Throw    
        }
    }
}