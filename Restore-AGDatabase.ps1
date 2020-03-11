[Cmdletbinding()]
Param (
    $SourceServer,
    $TargetServer,
    $AvailabilityGroup,
    $SourceDatabaseName,
    $TargetDatabaseName,
    $BackupFileLocation = "\\wpg1dd02\np_SqlBackup\ADHOC\$($SourceDatabaseName)_tmp.bak",
    $ExecuteAs = 'SQLSamurai',
    [datetime]$RestoreTime,
    [switch]$KeepPermissions,
    [switch]$DropUsers
)

#Stop on any error by default
$ErrorActionPreference = 'Stop'

$permissionsFile = ".\Permissions-$targetDatabaseName.sql"

#Determine primary
Write-Verbose "Determining primary node of the Availability Group"
foreach ($s in $TargetServer) {
    $srv = Connect-DbaInstance -SqlInstance $s
    if ($srv.AvailabilityGroups[$AvailabilityGroup].LocalReplicaRole -eq 'Primary') {
        $currentPrimary = $s
    }
}

if (!$currentPrimary) {
    throw 'Unable to determine primary replica of the AG'
}


Write-Verbose "Determining recovery model of the source database"
if ($d = Get-DbaDatabase -SqlInstance $SourceServer -Database $SourceDatabaseName) {
    $recoveryModel = $d.RecoveryModel
}

#Record permissions
if ($KeepPermissions -or $DropUsers) {
    $permissions = Export-DbaUser -SqlInstance $currentPrimary -Database $TargetDatabaseName
    Write-Verbose "Exported permissions from $currentPrimary.$targetDatabaseName`: $permissions"
    Write-Verbose "Storing permissions of $currentPrimary.$targetDatabaseName in a file $permissionsFile"
    $permissions | Out-File -FilePath $permissionsFile
}

#Remove target DB from AG
$srv = Connect-DbaInstance -SqlInstance $currentPrimary
if ($ag = $srv.Databases[$targetDatabaseName].AvailabilityGroupName) {
    Write-Verbose "Removing database $targetDatabaseName from AG $ag on $currentPrimary"
    $srv.AvailabilityGroups[$ag].AvailabilityDatabases[$targetDatabaseName].Drop()
}

if ($recoveryModel -eq 'Full') {
    #Restore the database on top of existing DBs
    foreach ($s in $TargetServer) {
        #Get backup history
        Write-Verbose "Loading backup history"
        $history = @()
        foreach ($s in $SourceServer) {
            $history += Get-DbaBackupHistory -SqlInstance $s -Database $SourceDatabaseName
        }
        #Initiating connection to the target server
        $conn = Connect-DbaInstance -SqlInstance $s -NonPooledConnection

        #Becoming a different user if specified - to change the default DB Owner
        if ($ExecuteAs) {
            $conn.Invoke("EXECUTE AS LOGIN = '$ExecuteAs' WITH NO REVERT")
        }
        $restoreSplat = @{
            SqlInstance          = $conn
            DatabaseName         = $TargetDatabaseName
            WithReplace          = $true
            NoRecovery           = $true
            ReplaceDbNameInFile  = $true
            TrustDbBackupHistory = $true
        }
        if ($RestoreTime) { $restoreSplat.RestoreTime = $RestoreTime }
        Write-Verbose "Initiating database restore from backup history to $s.$targetDatabaseName"
        $restore = $history | Restore-DbaDatabase @restoreSplat
        $restore
        if (!$restore.RestoreComplete) {
            throw "Restore from $backupFileLocation was not completed successfully on  $s.$targetDatabaseName"
        }
    }

    #Bring database online on primary
    Write-Verbose "Completing database restore on primary with recovery`: $currentPrimary.$targetDatabaseName"
    Restore-DbaDatabase -SqlInstance $currentPrimary -DatabaseName $targetDatabaseName -Recover -EnableException
}
else {
    #Now we need to convert the database to full and create a new backup

    #Initiating connection to the target server
    $conn = Connect-DbaInstance -SqlInstance $currentPrimary -NonPooledConnection

    #Becoming a different user if specified - to change the default DB Owner
    if ($ExecuteAs) {
        $conn.Invoke("EXECUTE AS LOGIN = '$ExecuteAs' WITH NO REVERT")
    }
    $restoreSplat = @{
        SqlInstance          = $conn
        DatabaseName         = $TargetDatabaseName
        WithReplace          = $true
        ReplaceDbNameInFile  = $true
        TrustDbBackupHistory = $true
    }
    if ($RestoreTime) { $restoreSplat.RestoreTime = $RestoreTime }
    #Get backup history
    Write-Verbose "Loading backup history"
    $history = @()
    foreach ($s in $SourceServer) {
        $history += Get-DbaBackupHistory -SqlInstance $s -Database $SourceDatabaseName
    }
    Write-Verbose "Initiating database restore from backup history to $currentPrimary.$targetDatabaseName"
    $restore = $history | Restore-DbaDatabase @restoreSplat -EnableException

    $restore

    if (!$restore.RestoreComplete) {
        throw "Restore from $backupFileLocation was not completed successfully on  $s.$targetDatabaseName"
    }

    Write-Verbose "Switching recovery mode to FULL for $currentPrimary.$targetDatabaseName"
    Set-DbaDbRecoveryModel -SqlInstance $currentPrimary -Database $targetDatabaseName -RecoveryModel Full -Confirm:$false
    $null = Invoke-DbaSqlQuery -SqlInstance $currentPrimary -Database $targetDatabaseName -Query 'CHECKPOINT'

    $currentDate = Get-Date
    Write-Verbose "Backing up the database again`: $currentPrimary.$targetDatabaseName to $backupFileLocation"
    $backup = Backup-DbaDatabase -SqlInstance $currentPrimary -Database $targetDatabaseName -BackupFileName $backupFileLocation -CompressBackup -Checksum -EnableException
    if (!$backup.BackupComplete) {
        throw "Backup to $backupFileLocation was not completed successfully on $SourceServer.$sourceDatabaseName"
    }

    #restore on all the secondaries
    foreach ($s in $TargetServer) {
        if ($s -ne $currentPrimary) {
            #Initiating connection to the target server
            $conn = Connect-DbaInstance -SqlInstance $s -NonPooledConnection

            #Becoming a different user if specified - to change the default DB Owner
            if ($ExecuteAs) {
                $conn.Invoke("EXECUTE AS LOGIN = '$ExecuteAs' WITH NO REVERT")
            }
            Write-Verbose "Initiating database restore on secondary $s`: $backupFileLocation to $s.$targetDatabaseName"
            $restore = $backup.Path | Restore-DbaDatabase -SqlInstance $conn -DatabaseName $targetDatabaseName -WithReplace -NoRecovery -ReplaceDbNameInFile

            $restore

            if (!$restore.RestoreComplete) {
                throw "Restore from $backupFileLocation was not completed successfully on  $s.$targetDatabaseName"
            }
        }
    }

    #restore any pending logs
    foreach ($s in $TargetServer) {
        if ($s -ne $currentPrimary) {
            if ($history = Get-DbaBackupHistory -SqlInstance $currentPrimary -Database $TargetDatabaseName -Since $currentDate -Type Log) {
                Write-Verbose "Restoring pending log backups on secondary $s.$targetDatabaseName"
                $history | Restore-DbaDatabase -SqlInstance $s -DatabaseName $targetDatabaseName -NoRecovery -ReplaceDbNameInFile -EnableException -Continue
            }
        }
    }
}


#Add the database to AG
Write-Verbose "Adding database $targetDatabaseName to the Availability Group $AvailabilityGroup"
$availabilityDb = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AvailabilityDatabase -ArgumentList @((Connect-DbaInstance -SqlInstance $currentPrimary).AvailabilityGroups[$AvailabilityGroup], $targetDatabaseName)
$availabilityDb.Create()

# wait a few seconds before enforcing secondaries

Start-Sleep 10

#Ensuring all secondaries managed to join the AG
foreach ($s in $TargetServer) {
    if ($s -ne $currentPrimary) {
        $agDb = (Connect-DbaInstance -SqlInstance $s).AvailabilityGroups[$AvailabilityGroup].AvailabilityDatabases[$TargetDatabaseName]
        Write-Verbose "Database $s.$TargetDatabaseName is joined to $AvailabilityGroup`: $($agDb.IsJoined)"
        if (!$agDb.IsJoined) {
            Write-Verbose "Manually joining the AG $AvailabilityGroup`:  $s.$TargetDatabaseName"
            $agDb.JoinAvailablityGroup()
        }
    }
}

#Drop users if requested
if ($DropUsers) {
    $users = Get-DbaDatabaseUser -SqlInstance $currentPrimary -Database $targetDatabaseName -ExcludeSystemUser
    foreach ($user in $users) {
        Write-Verbose "Dropping user $($user.Name) from $currentPrimary.$targetDatabaseName"
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
    Write-Verbose "Restoring permissions of $currentPrimary.$targetDatabaseName from a file $permissionsFile"
    Invoke-DbaSqlQuery -SqlInstance $currentPrimary -Database $targetDatabaseName -Query $permissions
}

#Repair orphaned users if needed
Repair-DbaOrphanUser -SqlInstance $currentPrimary -Database $targetDatabaseName

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