@{
	
	# Script module or binary module file associated with this manifest
	RootModule = 'ZipHelper.psm1'
	
	# Version number of this module.
	ModuleVersion = '0.1.0.0'
	
	# ID used to uniquely identify this module
    GUID = '97dac4a3-82a1-42e0-aec4-1aee66797120'
	
	# Author of this module
	Author = 'Kirill Kravtsov'
	
	# Company or vendor of this module
	CompanyName = ''
	
	# Copyright statement for this module
	Copyright = 'Kirill Kravtsov (@nvarscar) 2018. All rights reserved.'
	
	# Description of the functionality provided by this module
	Description = 'Tools to work with zip archives'
	
	# Minimum version of the Windows PowerShell engine required by this module
	PowerShellVersion = '3.0'
	
	# Name of the Windows PowerShell host required by this module
	PowerShellHostName = ''
	
	# Minimum version of the Windows PowerShell host required by this module
	PowerShellHostVersion = ''
	
	# Minimum version of the .NET Framework required by this module
	DotNetFrameworkVersion = '3.0'
	
	# Minimum version of the common language runtime (CLR) required by this module
	CLRVersion = '2.0.50727'
	
	# Processor architecture (None, X86, Amd64, IA64) required by this module
	ProcessorArchitecture = 'None'
	
	# Modules that must be imported into the global environment prior to importing
	# this module
	RequiredModules = @()
	
	# Assemblies that must be loaded prior to importing this module
	RequiredAssemblies = @()
	
	# Script files (.ps1) that are run in the caller's environment prior to
	# importing this module
	ScriptsToProcess = @()
	
	# Type files (.ps1xml) to be loaded when importing this module
	TypesToProcess = @()
	
	# Format files (.ps1xml) to be loaded when importing this module
	FormatsToProcess = @()
	
	# Modules to import as nested modules of the module specified in
	# ModuleToProcess
	NestedModules = @()
	
	# Functions to export from this module
	FunctionsToExport = @(
		'Add-ArchiveItem',
		'Expand-ArchiveItem',
		'Get-ArchiveItem',
		'Remove-ArchiveItem'
	)
	
	# Cmdlets to export from this module
	CmdletsToExport = '' 

	# Variables to export from this module
	VariablesToExport = ''

	# Aliases to export from this module
	AliasesToExport = '' #For performanace, list alias explicity

	# List of all modules packaged with this module
	ModuleList = @()

	# List of all files packaged with this module
	FileList = @()

	# Private data to pass to the module specified in ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
	PrivateData = @{
	
		#Support for PowerShellGet galleries.
		PSData = @{
		
			# Tags applied to this module. These help with module discovery in online galleries.
			Tags = @('Zip','Archive','Deflate','Unzip')
		
			# A URL to the license for this module.
			LicenseUri = 'https://github.com/nvarscar/psziphelper/blob/master/license.txt'
		
			# A URL to the main website for this project.
            ProjectUri = 'https://github.com/nvarscar/psziphelper'
		
			# A URL to an icon representing this module.
			# IconUri = ''
		
			# ReleaseNotes of this module
			# ReleaseNotes = ''
		
		} # End of PSData hashtable
	
	} # End of PrivateData hashtable
}







