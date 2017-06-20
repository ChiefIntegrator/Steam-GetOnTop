<# 
 .Synopsis 
	Scans .\SteamApps\ for app manifests, adds them to a lookup table and then writes that able to a JSON file.

 .Description 
    This script will search for app manifests in .\SteamApps\(*.acf), and extract the AppID, Name and Install Directory from each to store in a lookup table. This table is then
	output to a JSON file, to be used as a reference for matching Steam apps to install folders.

 .Parameter OutputFile
     This specifies the path to the JSON file for output. Default is ".\AppLookup.json"

 .Parameter InputFile
     This specifies the path to an existing JSON file so that a lookup table can be appended. Default is ".\AppLookup.json"

 .Example 
     .\Initialise-SteamAppLookup.ps1 -OutputFile ".\steamapps.json" -InputFile ".\existingapps.json"

     Description 
     ----------- 
     Reads in ".\existingapps.json", Scans .\SteamApps\ for app manifests, appends them and writes out to ".\steamapps.json"
 #>

[cmdletBinding(SupportsShouldProcess=$false)]
param(
	[Parameter(Position=0, Mandatory=$false)]
	[System.String]$OutputFile = ".\AppLookup.json"
	,
	[Parameter(Position=1, Mandatory=$false)]
	[System.String]$InputFile = ".\AppLookup.json"
)

Import-Module .\Modules\VDFTools

$steamPath = "$((Get-ItemProperty HKCU:\Software\Valve\Steam\).SteamPath)".Replace('/','\')

$LookupTablePath = ".\AppLookup.json"
if (Test-Path $LookupTablePath) {
	$AppLookup = Get-Content $LookupTablePath | ConvertFrom-Json
}

[array]$apps = @()

if ($AppLookup -ne $null) {
	[array]$apps += $AppLookup
}

ForEach ($file in (Get-ChildItem "$($steamPath)\SteamApps\*.acf") ) {
	$acf = ConvertFrom-VDF (Get-Content $file -Encoding UTF8)
	if ($acf.AppState.appID -notin $apps.AppID) {
		[array]$apps += $acf.AppState | Select-Object -Property AppId, Name, InstallDir
	}
}

$apps | ConvertTo-Json | Out-File $LookupTablePath -Encoding UTF8