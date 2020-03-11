[CmdletBinding()]
# Creates views and synonyms inside the -Database that reference to the tables of a different database on the same server.
# Optionally can use synonyms to build the following scenario: View -> Synonim -> Remote table
Param(
	[string]$Server,
	[string]$Database,
	[string]$ReferenceDatabase,
	[string[]]$Table,
	[string]$SynonymPrefix = "syn_",
	[string]$Schema,
	[string[]]$ReferenceSchema,
	[switch]$AsSynonyms,
	[switch]$DropExistingReferences
)
$refDb = Get-DbaDatabase -SqlInstance $Server -Database $ReferenceDatabase -EnableException
$viewDB = Get-DbaDatabase -SqlInstance $Server -Database $Database -EnableException
$scripts = @()
$newSchemas = @()
$tables = $refDb.tables

#apply filters if necessary
if ($Table) { 
	$tablesFilter = @()
	foreach ($t in $Table) {
		$tableSplit = $t.Split('.')
		if ($tableSplit.Count -gt 1) {
			$tablesFilter += @{ Name = $tableSplit[-1]; Schema = $tableSplit[-2] }
		}
		else {
			$tablesFilter += @{ Name = [string]$tableSplit; Schema = 'dbo' }
		}
	}
	$tables = $tables | ForEach-Object {
		foreach ($filter in $tablesFilter) {
			if ($_.Name -eq $filter.Name -and $_.Schema -eq $filter.Schema) { $_ }
		} 
	} 
}
if ($ReferenceSchema) { $tables = $tables | Where-Object {$_.Schema -in $ReferenceSchema} }

#check which schemas should exist on target
if ($Schema) { 
	$newSchemas += $Schema
}
else {
	foreach ($refSchema in $tables.Schema) {
		$newSchemas += $refSchema
	}
}
#check if the schema exist and add a statement to create it if needed
foreach ($currentSchema in ($newSchemas | Group-Object).Name ) {
	if (!$viewDB.Schemas[$currentSchema]) {
		if ($Schema) { 
			$createSchemaSql = "CREATE SCHEMA [$currentSchema]"
		}
		else { 
			$createSchemaSql = $refDb.Schemas[$currentSchema].Script()
		}
		$scripts += $createSchemaSql
	}
}

#Drop target reference objects if needed
if ($DropExistingReferences) {
	if ($Schema) {
		if ($views = ($viewDB.Views | Where-Object Schema -eq $Schema )) {
			$views.Drop()
		}
		if ($synonyms = ($viewDB.Synonyms | Where-Object Schema -eq $Schema )) {
			Write-Verbose "Removing all synonyms from schema $Schema in database $Database"
			$synonyms.Drop()
		}
	}
	else {
		throw 'DropExistingReferences can be used only with explicitly specified target schema name'
	}
}

foreach ($refTable in $tables) {
	# choose a target schema
	if ($Schema) { 
		$currentSchema = $Schema 
	}
	else { 
		$currentSchema = $refTable.Schema 
	}

	# prepare objects to replace {#} in the formatted strings
	$tName = $refTable.Name
	$refDbName = $refDb.Name
	$refSchema = $refTable.Schema
	#$objects = @($currentSchema, $table.Name, $refDb.Name, $SynonymPrefix)

	if ($AsSynonyms) {
		$createSynonymSQL = "CREATE SYNONYM [$currentSchema].[$SynonymPrefix$tName] FOR [$refDbName].[$refSchema].[$tName]"
		$createViewSql = "CREATE VIEW [$currentSchema].[$tName] AS SELECT * FROM [$currentSchema].[$SynonymPrefix$tName]"
		if (!$DropExistingReferences) {
			if ($synonym = ($viewDB.Synonyms | Where-Object { $_.Name -eq $SynonymPrefix + $refTable.name -and $_.Schema -eq $currentSchema })) {
				Write-Verbose "Removing synonym $currentSchema.$($SynonymPrefix + $refTable.Name)"
				$synonym.Drop()
			}
		}
		Write-Verbose "Generating script for the synonym $currentSchema.$($SynonymPrefix + $refTable.Name)"
		$scripts += $createSynonymSQL -f $objects
	}
	else {
		$createViewSql = "CREATE VIEW [$currentSchema].[$tName] AS SELECT * FROM [$refDbName].[$refSchema].[$tName]"
	}
	if (!$DropExistingReferences) {
		if ($view = ($viewDB.Views | Where-Object { $_.Name -eq $refTable.name -and $_.Schema -eq $currentSchema })) {
			Write-Verbose "Removing view $currentSchema.$($refTable.Name)"
			$view.Drop()
		}
	}
	Write-Verbose "Generating script for the view $currentSchema.$($refTable.Name)"
	$scripts += $createViewSql
}

Write-Verbose "Running the object creation script against $Server.$Database"
Write-Verbose $($scripts -join "`nGO`n")
Invoke-DbaSqlQuery -SqlInstance $Server -Database $Database -Query ($scripts -join "`nGO`n") -EnableException