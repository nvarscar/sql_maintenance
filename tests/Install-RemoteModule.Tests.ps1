Param (
	$SqlInstance = 'wpg1lsds02,7221',
	$SqlInstance2 = 'wpg1lsds02,7220'
)
if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }


$target = $SqlInstance.Split(',')[0].Split(':')[0]
$Path = "$here\etc\modules\ziphelper"
$SetExecutionPolicy = 'AllSigned'

Describe "Install-RemoteModule tests" {
    Context "Copy example module" {
        It "should copy the module to remote server" {
            { & $here\..\Install-RemoteModule.ps1 -ComputerName $target -Path $Path -Force  } | Should Not Throw
            $module = Get-Module $Path -ListAvailable
            $remoteModule = Invoke-Command -ComputerName $target -ScriptBlock { Get-Module $args[0] -ListAvailable } -ArgumentList $module.Name
            $remoteModule | Should Not BeNullOrEmpty
            $module.Version.CompareTo($remoteModule.Version) | Should Be 0
        }
        It "should not copy the module if the module version is the same" {
            $results = & $here\..\Install-RemoteModule.ps1 -ComputerName $target -Path $Path -Verbose 4>&1
            $module = Get-Module $Path -ListAvailable
            $remoteModule = Invoke-Command -ComputerName $target -ScriptBlock { Get-Module $args[0] -ListAvailable } -ArgumentList $module.Name
            $remoteModule | Should Not BeNullOrEmpty
            $module.Version.CompareTo($remoteModule.Version) | Should Be 0
            "Module $($module.Name) is up-to-date on $target" | Should BeIn $results.Message
        }
    }
    Context "Negative tests" {
        It "should show warning when computername is not available" {
            Mock Test-Connection -MockWith { $false }
            & $here\..\Install-RemoteModule.ps1 -ComputerName NoSuchComputer -Path $Path -WarningVariable warnVar 3>$null
            $warnVar | Should Be 'Host NoSuchComputer seems to be unavailable, skipping'
        }
        It "should throw when path is not found" {
            { & $here\..\Install-RemoteModule.ps1 -ComputerName $target -Path nonexisting\path\etc -CloneUrl $CloneUrl -Branch Nonexistingbranch } | Should Throw
        }
        It "should throw when no modules found in path" {
            { & $here\..\Install-RemoteModule.ps1 -ComputerName $target -Path $here\etc -CloneUrl $CloneUrl -Branch Nonexistingbranch } | Should Throw
        }
    }
}