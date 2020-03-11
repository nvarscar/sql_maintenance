Param (
	$SqlInstance = 'wpg1lsds02,7221',
    $SqlInstance2 = 'wpg1lsds02,7220'
)
if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }


$server = $SqlInstance
$currentDate = Get-Date
$dateString = [string]$currentDate.Year + ([string]$currentDate.Month).PadLeft(2, '0') + ([string]$currentDate.Day).PadLeft(2, '0') + ([string]$currentDate.Hour).PadLeft(2, '0') + ([string]$currentDate.Minute).PadLeft(2, '0') + ([string]$currentDate.Second).PadLeft(2, '0')
$srcDb = "View_Test_Src_$dateString"
$tgtDb = "View_Test_Tgt_$dateString"

$sqlDropDb = @"
IF EXISTS (SELECT * FROM sys.databases WHERE name = '{0}') 
BEGIN 
    IF EXISTS (SELECT * FROM sys.databases WHERE name = '{0}' AND state_desc = 'ONLINE') 
        ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
    DROP DATABASE [{0}]
END
"@
$sqlCreateDb = "CREATE DATABASE [{0}]"
$sqlCreateSchema = "CREATE SCHEMA [s2]"
$sqlCreateTable = "CREATE TABLE cdt_test (a int); INSERT INTO cdt_test VALUES (1); CREATE TABLE cdt_test2 (a int); CREATE TABLE s2.cdt_test3 (a int)"
$sqlCreateView = "CREATE VIEW cdt_test2 AS SELECT 1 AS A"
$sqlCreates1View = "CREATE SCHEMA [s1]
GO
CREATE VIEW s1.cdt_test2 AS SELECT 1 AS A"
$sqlCreateSynonym = "CREATE SYNONYM syn_cdt_test FOR sys.tables"

Describe "Add-CrossDatabaseView tests" {
	BeforeEach {
		$null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $server
		$null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $server
		$null = Invoke-DbaSqlQuery -Query ($sqlCreateDb -f $srcDb) -SqlInstance $server
		$null = Invoke-DbaSqlQuery -Query ($sqlCreateDb -f $tgtDb) -SqlInstance $server
		$null = Invoke-DbaSqlQuery -Query $sqlCreateSchema -SqlInstance $server -Database $srcDb
		$null = Invoke-DbaSqlQuery -Query $sqlCreateTable -SqlInstance $server -Database $srcDb
	}
	AfterAll {
		$null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $srcDb) -SqlInstance $server
		$null = Invoke-DbaSqlQuery -Query ($sqlDropDb -f $tgtDb) -SqlInstance $server
	}
	Context "Regular tests" {
		It "Adds views as direct SELECT *" {
			& $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database $tgtDb 
			$db = Get-DbaDatabase -SqlInstance $server -Database $tgtDb
			'cdt_test' | Should BeIn $db.Views.Name
			'cdt_test2' | Should BeIn $db.Views.Name
			Invoke-DbaSqlQuery -Query "select * from cdt_test" -SqlInstance $server -Database $tgtDb | % a | Should be 1
		}
		It "Adds views as SELECT * from synonyms, replacing existing objects" {
			$null = Invoke-DbaSqlQuery -Query $sqlCreateView -SqlInstance $server -Database $tgtDb
			$null = Invoke-DbaSqlQuery -Query $sqlCreateSynonym -SqlInstance $server -Database $tgtDb
			& $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database $tgtDb -AsSynonyms
			$db = Get-DbaDatabase -SqlInstance $server -Database $tgtDb
			'cdt_test' | Should BeIn $db.Views.Name
			'cdt_test2' | Should BeIn $db.Views.Name
			'syn_cdt_test' | Should BeIn $db.Synonyms.Name
			'syn_cdt_test2' | Should BeIn $db.Synonyms.Name
			Invoke-DbaSqlQuery -Query "select * from cdt_test" -SqlInstance $server -Database $tgtDb | % a | Should be 1
		}
	}
	Context "custom Table tests" {
		It "Adds views as direct SELECT *" {
			& $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database $tgtDb -Table cdt_test
			$db = Get-DbaDatabase -SqlInstance $server -Database $tgtDb
			'cdt_test' | Should BeIn $db.Views.Name
			'cdt_test2' | Should Not BeIn $db.Views.Name
			Invoke-DbaSqlQuery -Query "select * from cdt_test" -SqlInstance $server -Database $tgtDb | % a | Should be 1
		}
		It "Adds views as SELECT * from synonyms" {
			& $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database $tgtDb -AsSynonyms -Table cdt_test
			$db = Get-DbaDatabase -SqlInstance $server -Database $tgtDb
			'cdt_test' | Should BeIn $db.Views.Name
			'cdt_test2' | Should Not BeIn $db.Views.Name
			'syn_cdt_test' | Should BeIn $db.Synonyms.Name
			'syn_cdt_test2' | Should Not BeIn $db.Synonyms.Name
			Invoke-DbaSqlQuery -Query "select * from cdt_test" -SqlInstance $server -Database $tgtDb | % a | Should be 1
		}
	}
	Context "custom Schema tests" {
		It "Adds views as direct SELECT *" {
			& $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database $tgtDb -Schema s1
			$db = Get-DbaDatabase -SqlInstance $server -Database $tgtDb
			'cdt_test', 'cdt_test2' | ForEach-Object {
				$currentView = $_
				$db.Views | Where-Object { $_.Name -eq $currentView -and $_.Schema -eq 's1'} | Should Not BeNullOrEmpty
			}
			Invoke-DbaSqlQuery -Query "select * from s1.cdt_test" -SqlInstance $server -Database $tgtDb | % a | Should be 1
		}
		It "Adds views as SELECT * from synonyms, replacing existing objects" {
			& $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database $tgtDb -AsSynonyms -Schema s1
			$db = Get-DbaDatabase -SqlInstance $server -Database $tgtDb
			'cdt_test', 'cdt_test2' | ForEach-Object {
				$currentView = $_
				$db.Views | Where-Object { $_.Name -eq $currentView -and $_.Schema -eq 's1'} | Should Not BeNullOrEmpty
				$db.Synonyms | Where-Object { $_.Name -eq "syn_$currentView" -and $_.Schema -eq 's1'} | Should Not BeNullOrEmpty
			}
			Invoke-DbaSqlQuery -Query "select * from s1.cdt_test" -SqlInstance $server -Database $tgtDb | % a | Should be 1
		}
	}
	Context "custom ReferenceSchema tests" {
		It "Adds views as direct SELECT *" {
			& $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database $tgtDb -ReferenceSchema s2
			$db = Get-DbaDatabase -SqlInstance $server -Database $tgtDb
			'cdt_test' | Should Not BeIn $db.Views.Name
			'cdt_test2' | Should Not BeIn $db.Views.Name
			'cdt_test3' | Should BeIn $db.Views.Name
			$db.Views | Where-Object { $_.Name -eq 'cdt_test3' -and $_.Schema -eq 's2'} | Should Not BeNullOrEmpty
		}
		It "Adds views as SELECT * from synonyms, replacing existing objects" {
			& $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database $tgtDb -AsSynonyms -ReferenceSchema s2
			$db = Get-DbaDatabase -SqlInstance $server -Database $tgtDb
			'cdt_test' | Should Not BeIn $db.Views.Name
			'cdt_test2' | Should Not BeIn $db.Views.Name
			'syn_cdt_test' | Should Not BeIn $db.Synonyms.Name
			'syn_cdt_test2' | Should Not BeIn $db.Synonyms.Name
			'cdt_test3' | Should BeIn $db.Views.Name
			'syn_cdt_test3' | Should BeIn $db.Synonyms.Name
			$db.Views | Where-Object { $_.Name -eq 'cdt_test3' -and $_.Schema -eq 's2'} | Should Not BeNullOrEmpty
			$db.Synonyms | Where-Object { $_.Name -eq 'syn_cdt_test3' -and $_.Schema -eq 's2'} | Should Not BeNullOrEmpty
		}
	}
	Context "DropExistingReferences tests" {
		It "Drops all views in target Schema regardless of the source objects" {
			$null = Invoke-DbaSqlQuery -Query $sqlCreates1View -SqlInstance $server -Database $tgtDb
			$null = Invoke-DbaSqlQuery -Query $sqlCreateSynonym -SqlInstance $server -Database $tgtDb
			& $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database $tgtDb -Schema s1 -Table cdt_test -AsSynonyms -DropExistingReferences
			$db = Get-DbaDatabase -SqlInstance $server -Database $tgtDb
			'cdt_test' | Should BeIn $db.Views.Name
			'cdt_test2' | Should Not BeIn $db.Views.Name
			'syn_cdt_test' | Should BeIn $db.Synonyms.Name
			'syn_cdt_test2' | Should Not BeIn $db.Synonyms.Name
			Invoke-DbaSqlQuery -Query "select * from s1.cdt_test" -SqlInstance $server -Database $tgtDb | % a | Should be 1
		}
	}
	Context "Negative backup-restore tests" {
		It "throws when source server is unavailable" {
			{ & $here\..\Add-CrossDatabaseView.ps1 -Server 'localhost,12345' -ReferenceDatabase $srcDb -Database $tgtDb } | Should Throw    
		}
		It "throws when database is unavailable" {
			{ & $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database NonExistingDB } | Should Throw    
		}
		It "throws when reference database is unavailable" {
			{ & $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase NonExistingDatabase -Database $tgtDb } | Should Throw    
		}
		It "throws when DropExistingReferences is specified without a Schema" {
			{ & $here\..\Add-CrossDatabaseView.ps1 -Server $server -ReferenceDatabase $srcDb -Database $tgtDb -DropExistingReferences } | Should Throw
		}
	}
}