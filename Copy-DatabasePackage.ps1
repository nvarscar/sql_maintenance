[Cmdletbinding()]
Param (
    $SourceServer,
    $TargetServer = $SourceServer,
    $SourceDatabaseName,
    $TargetDatabaseName,
    $Path = "\\wpg1dd02\np_SqlBackup\ADHOC",
    $PublishXml = (Join-Path $PSScriptRoot 'etc\publish.xml'),
    [switch]$IncludeData,
    [switch]$KeepPermissions
)

#Stop on any error by default
$ErrorActionPreference = 'Stop'

# Construct export parameters
$exportProperties = "/p:IgnorePermissions=True /p:IgnoreUserLoginMappings=True"
if ($IncludeData) {
    $exportProperties += " /p:ExtractAllTableData=True"
}

#Export database to path
Write-Verbose "Starting the export from $SourceServer.$SourceDatabaseName to $Path"
$exportFile = Export-DbaDacpac -SqlInstance $SourceServer -Database $SourceDatabaseName -Path $Path -ExtendedProperties $exportProperties -EnableException
Write-Verbose "Export completed`: $exportFile"

#Record permissions
if ($dbObject = Get-DbaDatabase -SqlInstance $TargetServer -Database $TargetDatabaseName) {
	if ($KeepPermissions) {
		$permissions = Export-DbaUser -SqlInstance $TargetServer -Database $TargetDatabaseName
		Write-Verbose "Exported permissions from $TargetServer.$targetDatabaseName`: $permissions"
	}
	#Keep extended properties
	$xProperties = $dbObject.ExtendedProperties | Select-Object Name, Value
}


#publish dacpac with defined publish xml file
try {
	Write-Verbose "Starting the publication from $($exportFile.Path) to $TargetServer.$TargetDatabaseName"
	$xml = (Get-Item $PublishXml -ErrorAction Stop).FullName
	Publish-DbaDacpac -PublishXml $xml -Database $TargetDatabaseName -SqlInstance $TargetServer -Path $exportFile.Path -EnableException
}
catch {
	throw $_
}
finally {
    if ($newDbObject = Get-DbaDatabase -SqlInstance $TargetServer -Database $TargetDatabaseName) {
        #Restore extended props
        foreach ($xP in $xProperties) {
            if($xProp = $newDbObject.ExtendedProperties[$xP.Name]) {
                $xProp.Value = $xP.Value
                $xProp.Alter()
            }
            else {
                $xProp = [Microsoft.SqlServer.Management.Smo.ExtendedProperty]::new($newDbObject, $xP.Name, $xP.Value)
                $xProp.Create()
            }
        }

        #Fix orphans
        Repair-DbaOrphanUser -SqlInstance $TargetServer -Database $TargetDatabaseName

        #Restore permissions
        if ($KeepPermissions) {
            Write-Verbose "Restoring permissions of $TargetServer.$targetDatabaseName"
            Invoke-DbaSqlQuery -SqlInstance $TargetServer -Database $targetDatabaseName -Query $permissions
        }
    }

	#remove dacpac eventually
	if (Test-Path $exportFile.Path) {
		Write-Verbose "Removing dacpac file $($exportFile.Path)"
		Remove-Item $exportFile.Path
	}
}