[Cmdletbinding()]
Param (
	[Alias('Name')]
    [string]$Path,
    [string[]]$ComputerName,
	[string]$SetExecutionPolicy = 'AllSigned',
	[switch]$Force
)

# Verify that module has been downloaded\
if ($modules = Get-Module $Path -ListAvailable -ErrorAction Stop | Group-Object -Property Name | Foreach-Object { $_.Group | Sort-Object Version -Descending | Select-Object -First 1 } ) {
	$modules | Foreach-Object { Write-Verbose "Module $($_.Name) v$($_.Version -join ',') was found" }
}
else {
	throw "No modules found in $Path"
}

# compress the module folders and store the module dictionary list
$modulePath = @{}
foreach ($module in $modules) { 
    $parent = [System.IO.Path]::GetTempPath()
    $name = [System.IO.Path]::GetRandomFileName() + ".zip"
    $archivePath = (Join-Path $parent $name)
    if ((Split-Path $module.ModuleBase -Leaf) -eq $module.Version.ToString()) {
        $moduleBase = Split-Path $module.ModuleBase -Parent
    }
    else {
        $moduleBase = $module.ModuleBase
    }
    Compress-Archive -Path $moduleBase -DestinationPath $archivePath -Force -ErrorAction Stop
    Write-Verbose "Created archive $archivePath for module base $moduleBase"
    $modulePath += @{ $module.Name = $archivePath }
}

foreach ($computer in $ComputerName) {
    if (!(Test-Connection $computer -ErrorAction SilentlyContinue)) { 
        Write-Warning "Host $computer seems to be unavailable, skipping"
        continue
    }
    # Open RemoteSession
	Write-Verbose "Opening session to $computer"
    $session = New-PSSession -ComputerName $computer

    # Check powershell version
    $remotePowershellVersion = Invoke-Command -Session $session -ScriptBlock { $PSVersionTable }
	
    if ($remotePowershellVersion.PSVersion.Major -lt 3) {
        Write-Warning "Powershell $($remotePowershellVersion.PSVersion) is not suported, skipping $computer"
    }
    else {
        # Get execution policy
        $remoteExecutionPolicy = Invoke-Command -Session $session -ScriptBlock { Get-ExecutionPolicy -Scope LocalMachine }

        if ($remoteExecutionPolicy.Value -eq 'Restricted') {
            Write-Verbose "Setting execution policy to $SetExecutionPolicy (was $remoteExecutionPolicy) on $computer."
            Invoke-Command -Session $session -ScriptBlock { Set-ExecutionPolicy -ExecutionPolicy $args[0] -Scope LocalMachine -Force } -ArgumentList $SetExecutionPolicy
        }

        # Get remote PSModulePath location
        $remoteModulePath = Invoke-Command -Session $session -ScriptBlock { 
            $modulePath = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine") 
            foreach ($mp in $modulePath.Split(';')) {
                If (Test-Path $mp) { $mp; break }
            }
        }
		
        # Get remote temporary file name
        $remoteArchiveName = Invoke-Command -Session $session -ScriptBlock { 
            $parent = [System.IO.Path]::GetTempPath()
            $name = [System.IO.Path]::GetRandomFileName() + ".zip"
            return (Join-Path $parent $name)
        }
		
        foreach ($module in $modules) {
            # Check if module already exists and require updating; cleanup the folder if it does
            $updateNeeded = Invoke-Command -Session $session -ArgumentList $remoteModulePath, $module -ScriptBlock { 
                $modulePath = $args[0]
                $module = $args[1]
                if (!$module -or !$module.Name) {
                    Throw "Module parameter cannot be blank"
                }
                $path = Join-Path $modulePath $module.Name
                if (Test-Path $path) {
                    # Verify module version
                    $currentModule = Get-Module $path -ListAvailable -ErrorAction SilentlyContinue 
                    if ($currentModule -and $currentModule.Name -eq $module.Name -and $currentModule.Version.CompareTo($module.Version) -ge 0 ) {
                        return $false
                    }
                }
                return $true
            }
			
			$remoteModuleFolder = Join-Path $remoteModulePath $module.Name
            #triple check the folder before proceeding
            if ($remoteModuleFolder.Trim('\') -eq $remoteModulePath.Trim('\')) {
                Write-Warning "The module folder cannot be the same as PSModulePath environment variable($remoteModulePath), skipping $computer"
            }

            # Remove folder and copy files if needed
            if ($updateNeeded -or $Force) {
                if ($PSCmdlet.ShouldProcess($computer, "Removing folder $remoteModuleFolder")) {
                    Invoke-Command -Session $session -ArgumentList $remoteModuleFolder -ScriptBlock { 
                        if (Test-Path $args[0]) {
                            $null = Remove-Item $args[0] -Recurse -Force
                        }
                        $null = New-Item $args[0] -ItemType Directory
                    }
                }
                if ($PSCmdlet.ShouldProcess($computer, "Copying module $($module.Name)($($modulePath[$module.Name])) to folder $remoteModulePath")) {
                    Copy-Item -ToSession $session -Destination $remoteArchiveName -Path $modulePath[$module.Name]
                    # Extract files
                    Invoke-Command -Session $session -ArgumentList $remoteModulePath, $remoteArchiveName -ScriptBlock { 
                        Add-Type -AssemblyName "system.io.compression.filesystem"
                        [io.compression.zipfile]::ExtractToDirectory($args[1], $args[0])
                    }
                }
                # Get-ChildItem .\$($module.Name) -Exclude ".git*" | Copy-Item -ToSession $session -Destination $remoteModuleFolder -Recurse -Force 
            }
            else {
                Write-Verbose "Module $($module.Name) is up-to-date on $computer"
            }
        }
    }
    Remove-PSSession -Session $session
}
foreach ($module in $modules) { 
    Write-Verbose "Removing temporary file $($modulePath[$module.Name])"
    Remove-Item $modulePath[$module.Name]
}