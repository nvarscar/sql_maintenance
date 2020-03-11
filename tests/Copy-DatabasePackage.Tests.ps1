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
$srcDb = "test_src"
$tgtDb = "test_tgt"
$backupLocation = '\\wpg1dd02\np_SqlBackup\ADHOC\Tests'

$sqlDropDb = @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '{0}') 
BEGIN 
    IF EXISTS (SELECT * FROM sys.databases WHERE name = '{0}' AND state_desc = 'ONLINE') 
        ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
    DROP DATABASE [{0}]
END
"@
$sqlCreateDb = "CREATE DATABASE [{0}]"
$sqlCreateTable = "CREATE TABLE cdt_test (a int); INSERT INTO cdt_test VALUES (1)"
$sqlCreateTable2 = "CREATE TABLE cdt_test2 (a int)"
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
Describe "Copy-DatabasePackage tests" {
    BeforeEach {
        $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $src
        $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $src
        $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $tgt
        $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $tgt
        $null = Invoke-DbaSqlQuery -Query ($sqlCreateDb -f $srcDb) -SqlInstance $src
        $null = Invoke-DbaSqlQuery -Query $sqlCreateTable -SqlInstance $src -Database $srcDb
        $null = Invoke-DbaSqlQuery -Query $sqlGrants -SqlInstance $src -Database $srcDb
    }
    AfterAll {
		$null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $src
		$null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $src
        $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $tgt
        $null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $tgt
    }
	Context "Regular tests" {
		It "Copies the database structure within the same server" {
			& $here\..\Copy-DatabasePackage.ps1 -SourceServer $src -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -Path $backupLocation
			$db = (Connect-DbaInstance -SqlInstance $src).Databases[$tgtDb]
			$db.Name | Should Be $tgtDb
			$db.IsAccessible | Should Be $true
			$db.Status | Should Be 'Normal' 
            $db.Tables[0].Name | Should Be 'cdt_test'
            Invoke-DbaSqlQuery -Query "select * from cdt_test" -SqlInstance $src -Database $tgtDb | % a | Should be $null
		}
		It "Copies the database structure within the same server into existing database and removes the objects" {
            $null = Invoke-DbaSqlQuery -Query ($sqlCreateDb -f $tgtDb) -SqlInstance $src
			$null = Invoke-DbaSqlQuery -Query $sqlCreateTable2 -SqlInstance $src -Database $tgtDb
			$db = (Connect-DbaInstance -SqlInstance $src).Databases[$tgtDb]
			'cdt_test2' | Should BeIn $db.Tables.Name
			& $here\..\Copy-DatabasePackage.ps1 -SourceServer $src -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -Path $backupLocation -PublishXml "$here\..\etc\publish.DropObjects.xml"
			$db = (Connect-DbaInstance -SqlInstance $src).Databases[$tgtDb]
			$db.Name | Should Be $tgtDb
			$db.IsAccessible | Should Be $true
			$db.Status | Should Be 'Normal' 
            'cdt_test' | Should BeIn $db.Tables.Name
            'cdt_test2' | Should Not BeIn $db.Tables.Name
            Invoke-DbaSqlQuery -Query "select * from cdt_test" -SqlInstance $src -Database $tgtDb | % a | Should be $null
		}
		It "Copies the database structure within the same server into existing database and keeps the objects" {
            $null = Invoke-DbaSqlQuery -Query ($sqlCreateDb -f $tgtDb) -SqlInstance $src
			$null = Invoke-DbaSqlQuery -Query $sqlCreateTable2 -SqlInstance $src -Database $tgtDb
			$db = (Connect-DbaInstance -SqlInstance $src).Databases[$tgtDb]
			'cdt_test2' | Should BeIn $db.Tables.Name
			& $here\..\Copy-DatabasePackage.ps1 -SourceServer $src -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -Path $backupLocation
			$db = (Connect-DbaInstance -SqlInstance $src).Databases[$tgtDb]
			$db.Name | Should Be $tgtDb
			$db.IsAccessible | Should Be $true
			$db.Status | Should Be 'Normal' 
            'cdt_test' | Should BeIn $db.Tables.Name
            'cdt_test2' | Should BeIn $db.Tables.Name
            Invoke-DbaSqlQuery -Query "select * from cdt_test" -SqlInstance $src -Database $tgtDb | % a | Should be $null
		}
		It "Copies the database structure to a different server and move data as well" {
			& $here\..\Copy-DatabasePackage.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -Path $backupLocation -IncludeData
			$db = (Connect-DbaInstance -SqlInstance $tgt).Databases[$tgtDb]
			$db.Name | Should Be $tgtDb
			$db.IsAccessible | Should Be $true
			$db.Status | Should Be 'Normal'
            $db.Tables[0].Name | Should Be 'cdt_test'
            Invoke-DbaSqlQuery -Query "select * from cdt_test" -SqlInstance $tgt -Database $tgtDb | % a | Should be 1
		}
	}
	Context "Negative backup-restore tests" {
		It "throws when backup path is unavailable" {
			{ & $here\..\Copy-DatabasePackage.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -Path "\\localhost\somenone\existent\path.bak" *>$null } | Should Throw    
		}
		It "throws when source server is unavailable" {
			{ & $here\..\Copy-DatabasePackage.ps1 -SourceServer 'localhost,12345' -TargetServer $tgt -SourceDatabaseName $srcDb -TargetDatabaseName $tgtDb -Path $backupLocation } | Should Throw    
		}
		It "throws when target server is unavailable" {
			{ & $here\..\Copy-DatabasePackage.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName $srcDb -TargetServer NonExistingServer -TargetDatabaseName $tgtDb -Path $backupLocation } | Should Throw    
		}
		It "throws when source database is unavailable" {
			{ & $here\..\Copy-DatabasePackage.ps1 -SourceServer $src -TargetServer $tgt -SourceDatabaseName NonExistingDatabase -TargetDatabaseName $tgtDb -Path $backupLocation } | Should Throw    
		}
	}
}