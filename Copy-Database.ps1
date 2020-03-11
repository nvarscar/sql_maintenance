[Cmdletbinding()]
Param (
    $SourceServer,
    $TargetServer = $SourceServer,
    $SourceDatabaseName,
    $TargetDatabaseName,
    $BackupFileLocation = "\\wpg1dd02\np_SqlBackup\ADHOC\$($SourceDatabaseName)_tmp.bak",
    $ExecuteAs = 'SQLSamurai',
    [switch]$KeepPermissions,
    [switch]$DropUsers
)

#Stop on any error by default
$ErrorActionPreference = 'Stop'

$permissionsFile = ".\Permissions-$targetDatabaseName.sql"

#Run copy-only backup
if (Test-Path $backupFileLocation) {
    Write-Verbose "Removing old backup file $backupFileLocation"
    Remove-Item $backupFileLocation
}
Write-Verbose "Initiating database backup`: $SourceServer.$sourceDatabaseName to $backupFileLocation"
$backup = Backup-DbaDatabase -SqlInstance $SourceServer -Database $sourceDatabaseName -BackupFileName $backupFileLocation -CopyOnly -CompressBackup -Checksum -EnableException

if (!$backup.BackupComplete) {
    throw "Backup to $backupFileLocation was not completed successfully on $SourceServer.$sourceDatabaseName"
}

#Initiating connection to the target server
$conn = Connect-DbaInstance -SqlInstance $TargetServer -NonPooledConnection

#Becoming a different user if specified - to change the default DB Owner
if ($ExecuteAs) {
    $conn.Invoke("EXECUTE AS LOGIN = '$ExecuteAs' WITH NO REVERT")
}

#Record permissions
if ($KeepPermissions -or $DropUsers) {
    $permissions = Export-DbaUser -SqlInstance $conn -Database $TargetDatabaseName
    Write-Verbose "Exported permissions from $TargetServer.$targetDatabaseName`: $permissions"
    Write-Verbose "Storing permissions of $TargetServer.$targetDatabaseName in a file $permissionsFile"
    $permissions | Out-File -FilePath $permissionsFile
}

#Restore the database on top of existing DB
Write-Verbose "Initiating database restore`: $backupFileLocation to $TargetServer.$targetDatabaseName"
$restore = $backup | Restore-DbaDatabase -SqlInstance $conn -DatabaseName $targetDatabaseName -WithReplace -ReplaceDbNameInFile
$restore

if (!$restore.RestoreComplete) {
	throw "Restore from $backupFileLocation was not completed successfully on $TargetServer.$targetDatabaseName"
}

#Drop users if requested
if ($DropUsers) {
    $users = Get-DbaDatabaseUser -SqlInstance $TargetServer -Database $targetDatabaseName -ExcludeSystemUser
    foreach ($user in $users) {
        Write-Verbose "Dropping user $($user.Name) from $TargetServer.$targetDatabaseName"
        try {
            $user.Drop()
        }
        catch {
            # No need to throw at this point, maybe a user owns a schema of its own
            Write-Warning -Message $_
        }
    }
}

#Restore permissions
if ($KeepPermissions) {
    Write-Verbose "Restoring permissions of $TargetServer.$targetDatabaseName from a file $permissionsFile"
    Invoke-DbaSqlQuery -SqlInstance $TargetServer -Database $targetDatabaseName -Query $permissions
}

#Repair orphaned users if needed
Repair-DbaOrphanUser -SqlInstance $TargetServer -Database $targetDatabaseName

#Remove backup file
if (Test-Path $backupFileLocation) {
    Write-Verbose "Removing backup file $backupFileLocation"
    Remove-Item $backupFileLocation
}

#Remove permissions file
if (Test-Path $permissionsFile) {
    Write-Verbose "Removing permissions file $permissionsFile"
    Remove-Item $permissionsFile
}