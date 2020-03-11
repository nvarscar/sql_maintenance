param
(
    [string[]]$Path = '.',
    [string[]]$Tag,
    [string]$SqlInstance = 'wpg1lsds02,7221',
    [string]$SqlInstance2 = 'wpg1lsds02,7220'
	
)
if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

#Run each module function
$params = @{
    Script = @{
        Path = $Path
        Parameters = @{
			SqlInstance  = $SqlInstance
			SqlInstance2 = $SqlInstance2
        }
    }
}
if ($Tag) {
    $params += @{ Tag = $Tag}
}
Push-Location $here
Invoke-Pester @params
Pop-Location