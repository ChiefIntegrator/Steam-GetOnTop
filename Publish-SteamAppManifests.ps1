<# 
 .Synopsis 
	Scans the Steam folder for installed apps that don't have an app manifest, and creates app manifests after a sanity check by the user.

 .Description 
    This script will search for install folders in .\SteamApps\common, and compare install folders against app manifests in .\SteamApps. If any app manifests are missing,
	they will be displayed in a data table. The user has the option to recreate them, or tweak the data if it has been incorrectly matched. This largely automates the process 
	of Steam library migration and recovery.

 .Parameter LookupTablePath
	 Specifies a path to a JSON file containing lookup information for definitive matches for Steam AppIDs, Names and Install Directories. Default ".\appLookup.json"
	
 .Parameter IncludeGamesNotOwned
     When this switch is specified, the various search algorithms will compare against *all* Steam apps (slower). By default, this option is not enabled, and the searches
	 will only match against games owned by Steam users on this local machine.

 .Parameter SkipSanityCheck
     Not yet implemented, as the searches are not yet accurate or robust enough to justify it.

 .Parameter MaximumAmbiguousMatches
     This can be specified to override the default behaviour of only adding singular matches to the data table. Ambiguous matches will be added to the data table for sanity
	 checking if the number of matches for a query is less than the MaximumAmbiguousMatches set.
	 
 .Parameter LogLevel
     Sets the highest log message category that will by output to the log file and powershell host window. Accepted Values are "None", "Standard", "Verbose", "Debug" 

 .Example 
     .\Publish-SteamAppManifests.ps1 -MaximumAmbiguousMatches 5

     Description 
     ----------- 
     Generates a list a missing Steam app manifests, allowing up to 5 ambiguous matches to be sanity checked by the user.
 #>

[cmdletBinding(SupportsShouldProcess=$false)]
param(
	[Parameter(Mandatory=$false)]
	[string]$LookupTablePath = ".\appLookup.json"
	,
	[Parameter(Mandatory=$false)]
	[Switch]$IncludeGamesNotOwned
	,
	[Parameter(Mandatory=$false)]
	[Switch]$SkipSanityCheck
	,
	[Parameter(Mandatory=$false)]
	[int]$MaximumAmbiguousMatches = 1
	,
	[Parameter(Mandatory=$false)]
	[ValidateSet("None", "Standard", "Verbose", "Debug")] 
	[string]$LogLevel = "Standard"
)

# =========
# Functions
# =========

#region Functions
Function New-ACF {
<# 
 .Synopsis 
	Creates a new ACF (app manifest) file for a given Steam App ID, Name and install folder.

 .Description 
    This function will create a new ACF (app manifest) file for a given Steam App ID, Name and install folder in <steam root>\SteamApps\ . Most values are left at zero and will be updated by Steam when it validates the app manifest.

 .Parameter AppID
     Specifies the Steam AppID to be used.

 .Parameter AppName
     Specifies the application name that corresponds to the AppID.
	 
 .Parameter SteamLibrary
     Specifies the root folder of this steam library

 .Parameter AppFolder
     Specifies the installation folder name ($SteamLibrary\SteamApps\$AppFolder)

 .Example 
     New-ACF -AppID 400 -AppName "Portal" -SteamLibrary "C:\Steam" -AppFolder "Portal"

     Description 
     ----------- 
     Creates <steam root>\SteamApps\appmanifest_400.acf for Portal, installed in <steam root>\SteamApps\Portal
 #>
param(
	[Parameter(Position=0, Mandatory=$true)]
	[int]$AppID
	,
	[Parameter(Position=1, Mandatory=$true)]
	[ValidateNotNullOrEmpty()]
	[string[]]$AppName
	,
	[Parameter(Position=2, Mandatory=$true)]
	[ValidateNotNullOrEmpty()]
	[string[]]$SteamLibrary
	,
	[Parameter(Position=3, Mandatory=$true)]
	[ValidateNotNullOrEmpty()]
	[string[]]$AppFolder
)

	$acf = @"
"AppState"
{
	"appid"		"$($AppID)"
	"Universe"		"1"
	"name"		"$($AppName)"
	"StateFlags"		"2"
	"installdir"		"$($AppFolder)"
	"LastUpdated"		"0"
	"UpdateResult"		"0"
	"SizeOnDisk"		"0"
	"buildid"		"0"
	"LastOwner"		"76561197970761367"
	"BytesToDownload"		"0"
	"BytesDownloaded"		"0"
	"AutoUpdateBehavior"		"0"
	"AllowOtherDownloadsWhileRunning"		"0"
	"UserConfig"
	{
		"language"		"english"
	}
	"InstalledDepots"
	{
	}
	"MountedDepots"
	{
	}
}
"@
	$path = "$($SteamLibrary)\SteamApps\appmanifest_$($appID).acf"
	if ((Test-Path $path) -eq $false) {
		Out-File -InputObject $acf -FilePath $path -Encoding UTF8
		Write-Log -InputObject "Created app manifest for $($AppName) @ $($path)"
	} else {
		Write-Log -InputObject "App manifest for $($AppName) already exists @ $($path)"
	}
}

Function New-SanityCheckForm {
	$windowwidth = 1024
	$windowheight = 720
	
	# Create an empty Form
	$Form = New-Object System.Windows.Forms.Form
	$Form.width = $windowwidth
	$Form.height = $windowheight
	$Form.Text = "Sanity Check"
	$Form.ControlBox = $false
	$Form.ShowIcon = $false
	$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
	$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

	# Get the actual form space
	$formwidth = $Form.ClientRectangle.Width
	$formheight = $Form.ClientRectangle.Height
	
	# Cancel Button
	$Button = new-object System.Windows.Forms.Button
	$Button.Location = new-object System.Drawing.Size(($formwidth - 108), ($formheight - 32))
	$Button.Size = new-object System.Drawing.Size(100,24)
	$Button.Text = "Cancel"
	$Button.Add_Click({ $script:exit = $true })
	$Form.Controls.Add($Button)
	#$Form.CancelButton = $Button
	
	# Okay Button
	$Button = new-object System.Windows.Forms.Button
	$Button.Location = new-object System.Drawing.Size(($formwidth - 216), ($formheight - 32))
	$Button.Size = new-object System.Drawing.Size(100,24)
	$Button.Text = "Build ACFs"
	$Button.Add_Click({ $script:sanityChecked = $true; $script:exit = $true })
	$Form.Controls.Add($Button)
	#$Form.AcceptButton = $Button
	
	return $Form
}

Function New-SanityCheckDataGridView {
param(
	[Parameter(Position=0, Mandatory=$true)]
	[System.Windows.Forms.Form]$Form
)
	$formwidth = $Form.ClientRectangle.Width
	$formheight = $Form.ClientRectangle.Height
	
	# Define Cell Templates
	$dgvTextCell = New-Object System.Windows.Forms.DataGridViewTextBoxCell
	$dgvTextCell.Style.BackColor = [System.Drawing.Color]::White
	
	$dgvCheckBoxCell = New-Object System.Windows.Forms.DataGridViewCheckBoxCell
	$dgvCheckBoxCell.Style.BackColor = [System.Drawing.Color]::White
	
	# Create a Data Grid 
	$dgv = New-Object System.Windows.Forms.DataGridView
	$dgv.Name = "Result List"
	$dgv.Location = new-object System.Drawing.Size(20,20)
	$dgv.Size = new-object System.Drawing.Size(($formwidth - 40), ($formheight - 60))
	$dgv.MultiSelect = $false
	$dgv.AllowUserToAddRows = $false
	$dgv.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill #AllCells
	$dgv.AutoGenerateColumns = $false

	$dgvColumn = New-Object System.Windows.Forms.DataGridViewColumn
	$dgvColumn.Name = "AppID"
	$dgvColumn.DataPropertyName = "AppID"
	$dgvColumn.HeaderText = "AppID"
	$dgvColumn.CellTemplate = $dgvTextCell
	$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells
	$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
	#$dgvColumn.set_ReadOnly($true)
	$dgv.Columns.Add($dgvColumn) | Out-Null
	 
	$dgvColumn = New-Object System.Windows.Forms.DataGridViewColumn
	$dgvColumn.Name = "Name"
	$dgvColumn.DataPropertyName = "Name"
	$dgvColumn.HeaderText = "Name"
	$dgvColumn.CellTemplate = $dgvTextCell
	$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells
	$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
	#$dgvColumn.set_ReadOnly($true)
	$dgv.Columns.Add($dgvColumn) | Out-Null
	 
	$dgvColumn = New-Object System.Windows.Forms.DataGridViewColumn
	$dgvColumn.Name = "Folder"
	$dgvColumn.DataPropertyName = "Folder"
	$dgvColumn.HeaderText = "Folder"
	$dgvColumn.CellTemplate = $dgvTextCell
	$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells
	$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
	$dgvColumn.set_ReadOnly($true)
	$dgv.Columns.Add($dgvColumn) | Out-Null
	
	$dgvColumn = New-Object System.Windows.Forms.DataGridViewColumn
	$dgvColumn.Name = "Library"
	$dgvColumn.DataPropertyName = "Library"
	$dgvColumn.HeaderText = "Library"
	$dgvColumn.CellTemplate = $dgvTextCell
	$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells
	$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
	$dgvColumn.set_ReadOnly($true)
	$dgv.Columns.Add($dgvColumn) | Out-Null
	 
	$dgvColumn = New-Object System.Windows.Forms.DataGridViewColumn
	$dgvColumn.Name = "Query"
	$dgvColumn.DataPropertyName = "Query"
	$dgvColumn.HeaderText = "Query"
	$dgvColumn.CellTemplate = $dgvTextCell
	$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells
	$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
	$dgvColumn.set_ReadOnly($true)
	$dgv.Columns.Add($dgvColumn) | Out-Null
	 
	$dgvColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
	$dgvColumn.Name = "Valid"
	$dgvColumn.DataPropertyName = "Valid"
	$dgvColumn.HeaderText = "Valid?"
	$dgvColumn.CellTemplate = $dgvCheckBoxCell
	$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells
	$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
	#$dgvColumn.set_ReadOnly($true)
	$dgvColumn.TrueValue = $true
	$dgvColumn.FalseValue = $false
	$dgv.Columns.Add($dgvColumn) | Out-Null

	$dgvColumn = New-Object System.Windows.Forms.DataGridViewColumn
	$dgvColumn.Name = "Blank"
	$dgvColumn.HeaderText = ""
	$dgvColumn.CellTemplate = $dgvTextCell
	$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
	$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
	$dgvColumn.set_ReadOnly($true)
	$dgv.Columns.Add($dgvColumn) | Out-Null
	 
	$dgv.Sort($dgv.Columns["Name"], [System.ComponentModel.ListSortDirection]::Ascending)
	$dgv.AutoResizeColumns()

	$dgv.Add_CellValidating({
		if ($dgv.Columns[$_.ColumnIndex].Name -eq "AppID") {
			$id = $_.FormattedValue
			if ($id.ToString() -match "[\D\-]") {
				$dgv.Rows[$_.RowIndex].ErrorText = "AppID can only contain digits"
				$_.Cancel = $true
			}
			
			$folderName = ($matchTable | Where-Object {$_.AppID -eq $id}).Folder
			if ( ($id -ne -1) -and ($folderName -ne $null) -and ($dgv.Rows.SharedRow($_.RowIndex).Cells["Folder"].Value -ne $folderName) ) {
				$dgv.Rows[$_.RowIndex].ErrorText = "AppID is already in list (Folder: $($folderName))"
				$_.Cancel = $true
			}
		}
		elseif ($dgv.Columns[$_.ColumnIndex].Name -eq "Name") {
			$name = $_.FormattedValue
			
			$folderName = ($matchTable | Where-Object {$_.Name -eq $name}).Folder
			if ( ($name -ne "????") -and ($folderName -ne $null) -and ($dgv.Rows.SharedRow($_.RowIndex).Cells["Folder"].Value -ne $folderName ) ) {
				$dgv.Rows[$_.RowIndex].ErrorText = "AppName is already in list (Folder: $($folderName))"
				$_.Cancel = $true
			}
		}
		
	})

	$dgv.Add_CellEndEdit({
		if ($dgv.Columns[$_.ColumnIndex].Name -eq "AppID") {
			$dgv.Rows.SharedRow($_.RowIndex).Cells["Query"].Value = "Modified by User"
			$id = $dgv.Rows.SharedRow($_.RowIndex).Cells["AppID"].Value
			$appinfo = ($steamapplist.applist.apps.app | Where-Object {$_.appID -eq $id})
			if ($appinfo -ne $null) {
				$dgv.Rows.SharedRow($_.RowIndex).Cells["Name"].Value = $appinfo.Name	
			} else { 
				$dgv.Rows.SharedRow($_.RowIndex).Cells["Name"].Value = "????"
				$dgv.Rows.SharedRow($_.RowIndex).Cells["Valid"].Value = $false
			}
			$dgv.Rows[$_.RowIndex].ErrorText = [System.String]::Empty
		}
		elseif ($dgv.Columns[$_.ColumnIndex].Name -eq "Name") {
			$dgv.Rows.SharedRow($_.RowIndex).Cells["Query"].Value = "Modified by User"
			$name = $dgv.Rows.SharedRow($_.RowIndex).Cells["Name"].Value
			$appinfo = ($steamapplist.applist.apps.app | Where-Object {$_.Name -eq $name})
			if ($appinfo -ne $null) {
				$dgv.Rows.SharedRow($_.RowIndex).Cells["AppID"].Value = $appinfo.AppID	
			} else { 
				$dgv.Rows.SharedRow($_.RowIndex).Cells["AppID"].Value = -1
				$dgv.Rows.SharedRow($_.RowIndex).Cells["Valid"].Value = $false
			}
			$dgv.Rows[$_.RowIndex].ErrorText = [System.String]::Empty
		}
	})
	
	$Form.Controls.Add($dgv) | Out-Null
	
	return $dgv
}

#endregion

# Main
# ====

# Load Forms assemblies
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

# Import Modules
Import-Module .\Modules\SteamTools
Import-Module .\Modules\LogTools

#region Initialisation
if ($IncludeGamesNotOwned -eq $true) {
	Write-Host -ForegroundColor Yellow -BackgroundColor Black "Running with the 'IncludeGamesNotOwned' option set will greatly impact performance, as it will run each query against a list of ~43,000 appIDs. It *decreases* the chances of successful matches due to increased ambiguity, and increases the risk of erroneous matches. If you're okay with that, go nuts."
	Write-Host  "`nAre you sure? ('Y' to continue, any other key to exit)"
	$keyPress = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
	if ($keyPress.Character -ne 'Y') {
		exit
	}
}

if ($SkipSanityCheck -eq $true) {
	Write-Host -ForegroundColor Red -BackgroundColor Black "This may be implemented at a later date. For now, sanity prevails - always."
	Write-Host -ForegroundColor Red -BackgroundColor Black "Please run the script again without -SkipSanityCheck"
	exit
}

$log = ".\Publish-SteamAppManifests.log"
Set-LogPath $log
Set-LogLevel $LogLevel
New-Item -Path $log -ItemType File -Force  | Out-Null

Write-LogHeader -InputObject "Publish-SteamAppManifests.ps1"

# Get steam library locations
$steamPath = Get-SteamPath
Write-Log -InputObject "Steam is installed in '$steamPath'"
[array]$steamLibraries += $steamPath
$config = ConvertFrom-VDF (Get-Content "$($steamPath)\config\config.vdf")
ForEach($library in ($config.InstallConfigStore.Software.Valve.Steam | Get-Member | Where-Object {$_.Name -match "BaseInstallFolder"})) {
	$path = ($config.InstallConfigStore.Software.Valve.Steam.($library.name)).Replace("\\", "\")
	Write-Log -InputObject "Additional Steam library found in '$($path)'"
	[array]$steamLibraries += $path
}

# Preload Steam App List
Write-Log -InputObject "Loading app info from Steam Store..."
try {
	$steamapplist = (Invoke-WebRequest "http://api.steampowered.com/ISteamApps/GetAppList/v0001/" -UseBasicParsing).Content | ConvertFrom-Json
}
catch {
	Write-LogFooter "Execution failed - $($_.Exception)"
	#throw
}
Write-Log -InputObject "... $(($steamapplist.applist.apps.app).count) IDs enumerated"

# Preload Lookup Table
Write-Log -InputObject "Loading AppID Lookup Table from file '$($LookupTablePath)' ..."
if (Test-Path $LookupTablePath) {
	$appLookup = Get-Content $LookupTablePath | ConvertFrom-Json
	$count = ($appLookup).count
} else {
	Write-Log -InputObject "AppID Lookup data not found at $($LookupTablePath)"
	$count = 0
}
Write-Log -InputObject "... $($count) IDs enumerated"

$disclaimer = [System.String]::Empty

if ($IncludeGamesNotOwned -eq $false) {
	# Set the disclaimer for future warnings
	$disclaimer = " in games owned by local users"
	
	# Get games owned by local users
	Write-Log -InputObject "Loading AppIDs for games owned by Local Users..."
	$libraryIDs = @()
	ForEach ($user in (get-childitem "$($steamPath)\userdata" | Where-Object {$_.BaseName -ne "0"})) {
		try {
			[xml]$xmlLibrary = (Invoke-WebRequest "http://steamcommunity.com/profiles/$(Get-SteamID64 -SteamID3 ($user.BaseName.ToInt32($null)))/games?tab=all&xml=1" -UseBasicParsing).Content
			if ($xmlLibrary.gamesList.error -eq $null) {
				$libraryIDs += $xmlLibrary.gamesList.games.game.appID | Where-Object {$_ -notin $libraryIDs}
			} else {
				$errortext = $xmlLibrary.gamesList.error."#cdata-section"
				$username = $xmlLibrary.gamesList.steamID."#cdata-section"
				Write-Log -InputObject "Could not retrieve owned games for '$($username)' - Error: $($errortext)" -MessageLevel "Warning"
			}
		}
		catch {
			Write-Log -InputObject "Could not retrieve owned games for '$($user)' - Error: $($_.Exception)" -MessageLevel "Warning"
		}
	}
	Write-Log -InputObject "... $($libraryIDs.count) IDs enumerated"
	
	# Filter games to owned only
	Write-Log -InputObject "Filtering Apps to owned only... (this may take a minute or two)"
	$mysteamapplist = $steamapplist.applist.apps.app | Where-Object {$_.appid -in $libraryIDs }
	Write-Log -InputObject "... Done!"
} else {
	$mysteamapplist = $steamapplist.applist.apps.app
}

# DEBUG
#$mysteamapplist | Export-CSV ".\mysteamapplist.csv" -Encoding UTF8
#$mysteamapplist = Import-CSV ".\mysteamapplist.csv"

ForEach ($steamLibrary in $steamLibraries) {
	# Get Folders
	Write-Log -InputObject "Getting install directories from $($steamLibrary)\SteamApps\Common ..."
	$folders = Get-ChildItem "$($steamLibrary)\SteamApps\Common\" | Select-Object -Property Name
	Write-Log -InputObject "... $($folders.count) directories enumerated"

	# Build a table to store relevant data
	$matchTable = New-Object System.Data.DataTable
	$newColumn = $matchTable.Columns.Add("AppID")
	$newColumn.DataType = [System.Int32]
	$newColumn = $matchTable.Columns.Add("Name")
	$newColumn.DataType = [System.String]
	$newColumn = $matchTable.Columns.Add("Folder")
	$newColumn.DataType = [System.String]
	$newColumn = $matchTable.Columns.Add("Library")
	$newColumn.DataType = [System.String]
	$newColumn = $matchTable.Columns.Add("Query")
	$newColumn.DataType = [System.String]
	$newColumn = $matchTable.Columns.Add("Valid")
	$newColumn.DataType = [System.Boolean]
	#endregion

	#region Data matching
	$remaining = $folders.name
	$unmatched = @()
	$lastMatchedCount = 0
	$matchTable.BeginLoadData()

	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "Trying AppID Lookup table ..."
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	ForEach ($folder in $remaining) {
		$id = ($appLookup | Where-Object {$_.installdir -eq $folder }).appid
		if ($id -ne $null) {
			if ($id.Count -eq 1) {
				$name = ($appLookup | Where-Object {$_.appid -eq $id }).name
				if ($name -eq $null) {
					$name = ($mysteamapplist | Where-Object {$_.appid -eq $id }).name
				}
				if ($name -ne $null) {
					$path = "$($steamPath)\SteamApps\appmanifest_$($id).acf"
					if ((Test-Path $path) -eq $false) {
						Write-Log -InputObject "App manifest for '$($name)' is missing"
						$matchTable.LoadDataRow(@($id, $name, $folder, $steamLibrary, "Lookup Table", $true), $true) | Out-Null
					} else {
						Write-Log -InputObject "App manifest for '$($name)' already exists @ $($path)" -MessageLevel "Verbose"
					}
				} else {
					$unmatched += $folder
				}
			} else {
				Write-Log -InputObject "Search term '$($folder)' returned $($id.count) results"
				$unmatched += $folder
			}
		} else {
			$unmatched += $folder
		}
	}
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "... query complete. $($matchTable.Rows.count - $lastMatchedCount) missing app manifest(s) ($($matchTable.Rows.count) total), $($unmatched.count) unmatched"
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"

	$lastMatchedCount = $matchTable.Rows.count
	$remaining = $unmatched
	$unmatched = @()

	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "Trying (Name -eq Install Directory) ..."
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	ForEach ($folder in $remaining) {
		$apps = ($mysteamapplist | Where-Object {$_.name -eq $folder })
		if ($apps -ne $null) {
			$definitiveMatch = $false;
			ForEach ($app in $apps) {
				$path = "$($steamPath)\SteamApps\appmanifest_$($app.AppID).acf"
				if ((Test-Path $path) -eq $true) {
					$acf = ConvertFrom-VDF (Get-Content $path)
					if ($acf.AppState.InstallDir -eq $folder) {
						Write-Log -InputObject "App manifest for '$($app.Name)' already exists @ $($path)" -MessageLevel "Verbose"
						$definitiveMatch = $true
						if ($app.AppID -notin $appLookup.AppID) {
							Write-Log -InputObject "$($app.Appid) : $($folder) not in Lookup Table - adding" -MessageLevel "Debug"
							[array]$appLookup += $acf.AppState | Select-Object -Property AppId, InstallDir
						}
						break
					}
				}
			}
			if (-not $definitiveMatch) {
				if ($apps.Count -le $MaximumAmbiguousMatches) {
					ForEach ($app in $apps) {
						$path = "$($steamPath)\SteamApps\appmanifest_$($app.AppID).acf"
						if ((Test-Path $path) -eq $false) {
							Write-Log -InputObject "App manifest for '$($app.Name)' may be missing"
							$matchTable.LoadDataRow(@($app.AppID, $app.Name, $folder, $steamLibrary, "-eq '$($folder)'", ($apps.appID.count -eq 1)), $true) | Out-Null
						}
					}
				} else {
					Write-Log -InputObject "Search term '$($folder)' returned too many results ($($apps.count) matches)"
					$unmatched += $folder
				}
			}
		} else {
			$unmatched += $folder
		}
	}
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "... query complete. $($matchTable.Rows.count - $lastMatchedCount) missing app manifest(s), $($unmatched.count) unmatched"
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"


	$lastMatchedCount = $matchTable.Rows.count
	$remaining = $unmatched
	$unmatched = @()

	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "Trying (Name -match Install Directory) ..."
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	ForEach ($folder in $remaining) {
		$apps = ($mysteamapplist | Where-Object {$_.name -match $folder })
		if ($apps -ne $null) {
			$definitiveMatch = $false;
			ForEach ($app in $apps) {
				$path = "$($steamPath)\SteamApps\appmanifest_$($app.AppID).acf"
				if ((Test-Path $path) -eq $true) {
					$acf = ConvertFrom-VDF (Get-Content $path)
					if ($acf.AppState.InstallDir -eq $folder) {
						Write-Log -InputObject "App manifest for '$($app.Name)' already exists @ $($path)" -MessageLevel "Verbose"
						$definitiveMatch = $true
						if ($app.AppID -notin $appLookup.AppID) {
							Write-Log -InputObject "$($app.Appid) : $($folder) not in Lookup Table - adding" -MessageLevel "Debug"
							[array]$appLookup += $acf.AppState | Select-Object -Property AppId, InstallDir
						}
						break
					}
				}
			}
			if (-not $definitiveMatch) {
				if ($apps.Count -le $MaximumAmbiguousMatches) {
					ForEach ($app in $apps) {
						$path = "$($steamPath)\SteamApps\appmanifest_$($app.AppID).acf"
						if ((Test-Path $path) -eq $false) {
							Write-Log -InputObject "App manifest for '$($app.Name)' may be missing"
							$matchTable.LoadDataRow(@($app.AppID, $app.Name, $folder, $steamLibrary, "-match '$($folder)'", ($apps.appID.count -eq 1)), $true) | Out-Null
						}
					}
				} else {
					Write-Log -InputObject "Search term '$($folder)' returned too many results ($($apps.count) matches)"
					$unmatched += $folder
				}
			}
		} else {
			$unmatched += $folder
		}
	}
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "... query complete. $($matchTable.Rows.count - $lastMatchedCount) missing app manifest(s) ($($matchTable.Rows.count) total), $($unmatched.count) unmatched"
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"

	$lastMatchedCount = $matchTable.Rows.count
	$remaining = $unmatched
	$unmatched = @()

	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "Trying (Name -match [Install Directory, Split by ' ']) ..."
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	ForEach ($folder in $remaining) {
		$words = $folder.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
		$found = $false
		$patterns = @()
		For ($i = $words.count; $i -gt 0; $i--) {
			$pattern = ""
			For ($j = 0; $j -lt $i; $j++) {
				$pattern += "$($words[$j]).*"
			}
			$patterns += $pattern
		}
		ForEach ($pattern in $patterns) {
			if (-not $found) {
				$apps = ($mysteamapplist | Where-Object {$_.name -match $pattern })
				if ($apps -ne $null) {
					$definitiveMatch = $false;
					ForEach ($app in $apps) {
						$path = "$($steamPath)\SteamApps\appmanifest_$($app.AppID).acf"
						if ((Test-Path $path) -eq $true) {
							$acf = ConvertFrom-VDF (Get-Content $path)
							if ($acf.AppState.InstallDir -eq $folder) {
								Write-Log -InputObject "App manifest for '$($app.Name)' already exists @ $($path)" -MessageLevel "Verbose"
								$definitiveMatch = $true
								$found = $true
								if ($app.AppID -notin $appLookup.AppID) {
									Write-Log -InputObject "$($app.Appid) : $($folder) not in Lookup Table - adding" -MessageLevel "Debug"
									[array]$appLookup += $acf.AppState | Select-Object -Property AppId, InstallDir
								}
								break
							}
						}
					}
					if (-not $definitiveMatch) {
						if ($apps.Count -le $MaximumAmbiguousMatches) {
							ForEach ($app in $apps) {
								$path = "$($steamPath)\SteamApps\appmanifest_$($app.AppID).acf"
								if ((Test-Path $path) -eq $false) {
									Write-Log -InputObject "App manifest for '$($app.Name)' may be missing"
									$matchTable.LoadDataRow(@($app.AppID, $app.Name, $folder, $steamLibrary, "-match '$($pattern)'", ($apps.appID.count -eq 1)), $true) | Out-Null
									$found = $true
								}
							}
						} else {
							Write-Log -InputObject "Search term '$($pattern)' (Folder: '$($folder) returned too many results ($($apps.count) matches)"
						}
					} else {
						break
					}
				}
			}
		}
		if (-not $found) {
			$unmatched += $folder
		}
	}
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "... query complete. $($matchTable.Rows.count - $lastMatchedCount) missing app manifest(s) ($($matchTable.Rows.count) total), $($unmatched.count) unmatched"
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"

	$lastMatchedCount = $matchTable.Rows.count
	$remaining = $unmatched
	$unmatched = @()

	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "Trying (Name -match [Install Directory, Split by Uppercase letters]) ..."
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	ForEach ($folder in $remaining) {
		if ($folder -match "\s+") { #
			$unmatched += $folder
			continue;
		}
		$regex = (Select-String -InputObject $folder -Pattern "(([A-Z]{1}[a-z]+)(?:\s*))+" -CaseSensitive)
		$words = $null
		if ($regex -ne $null) {
			$captures = $regex.Matches.Groups[$regex.Matches.Groups.count - 1].Captures
			if ($captures.count -gt 1) {
				$words = $captures.Value
			}
		}
		$found = $false
		$patterns = @()
		For ($i = $words.count; $i -gt 0; $i--) {
			$pattern = ""
			For ($j = 0; $j -lt $i; $j++) {
				$pattern += "$($words[$j]).*"
			}
			$patterns += $pattern
		}
		ForEach ($pattern in $patterns) {
			if (-not $found) {
				$apps = ($mysteamapplist | Where-Object {$_.name -match $pattern })
				if ($apps -ne $null) {
					$definitiveMatch = $false;
					ForEach ($app in $apps) {
						$path = "$($steamPath)\SteamApps\appmanifest_$($app.AppID).acf"
						if ((Test-Path $path) -eq $true) {
							$acf = ConvertFrom-VDF (Get-Content $path)
							if ($acf.AppState.InstallDir -eq $folder) {
								Write-Log -InputObject "App manifest for '$($app.Name)' already exists @ $($path)" -MessageLevel "Verbose"
								$definitiveMatch = $true
								$found = $true
								if ($app.AppID -notin $appLookup.AppID) {
									Write-Log -InputObject "$($app.Appid) : $($folder) not in Lookup Table - adding" -MessageLevel "Debug"
									[array]$appLookup += $acf.AppState | Select-Object -Property AppId, InstallDir
								}
								break
							}
						}
					}
					if (-not $definitiveMatch) {
						if ($apps.Count -le $MaximumAmbiguousMatches) {
							ForEach ($app in $apps) {
								$path = "$($steamPath)\SteamApps\appmanifest_$($app.AppID).acf"
								if ((Test-Path $path) -eq $false) {
									Write-Log -InputObject "App manifest for '$($app.Name)' may be missing"
									$matchTable.LoadDataRow(@($app.AppID, $app.Name, $folder, $steamLibrary, "-match '$($pattern)'", ($apps.appID.count -eq 1)), $true) | Out-Null
									$found = $true
								}
							}
						} else {
							Write-Log -InputObject "Search term '$($pattern)' (Folder: '$($folder) returned too many results ($($apps.count) matches)"
						}
					} else {
						break
					}
				}
			}
		}
		if (-not $found) {
			$unmatched += $folder
		}
	}
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "... query complete. $($matchTable.Rows.count - $lastMatchedCount) missing app manifest(s) ($($matchTable.Rows.count) total), $($unmatched.count) unmatched"
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"

	$lastMatchedCount = $matchTable.Rows.count
	$remaining = $unmatched
	$unmatched = @()

	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "Trying (Name -match [Install Directory, Split by '_']) ..."
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	ForEach ($folder in $remaining) {
		$words = $folder.Split("_", [System.StringSplitOptions]::RemoveEmptyEntries)
		$found = $false
		$patterns = @()
		For ($i = $words.count; $i -gt 0; $i--) {
			$pattern = ""
			For ($j = 0; $j -lt $i; $j++) {
				$pattern += "$($words[$j]).*"
			}
			$patterns += $pattern
		}
		ForEach ($pattern in $patterns) {
			if (-not $found) {
				$apps = ($mysteamapplist | Where-Object {$_.name -match $pattern })
				if ($apps -ne $null) {
					$definitiveMatch = $false;
					ForEach ($app in $apps) {
						$path = "$($steamPath)\SteamApps\appmanifest_$($app.AppID).acf"
						if ((Test-Path $path) -eq $true) {
							$acf = ConvertFrom-VDF (Get-Content $path)
							if ($acf.AppState.InstallDir -eq $folder) {
								Write-Log -InputObject "App manifest for '$($app.Name)' already exists @ $($path)" -MessageLevel "Verbose"
								$definitiveMatch = $true
								$found = $true
								if ($app.AppID -notin $appLookup.AppID) {
									Write-Log -InputObject "$($app.Appid) : $($folder) not in Lookup Table - adding" -MessageLevel "Debug"
									[array]$appLookup += $acf.AppState | Select-Object -Property AppId, InstallDir
								}
								break
							}
						}
					}
					if (-not $definitiveMatch) {
						if ($apps.Count -le $MaximumAmbiguousMatches) {
							ForEach ($app in $apps) {
								$path = "$($steamPath)\SteamApps\appmanifest_$($app.AppID).acf"
								if ((Test-Path $path) -eq $false) {
									Write-Log -InputObject "App manifest for '$($app.Name)' may be missing"
									$matchTable.LoadDataRow(@($app.AppID, $app.Name, $folder, $steamLibrary, "-match '$($pattern)'", ($apps.appID.count -eq 1)), $true) | Out-Null
									$found = $true
								}
							}
						} else {
							Write-Log -InputObject "Search term '$($pattern)' (Folder: '$($folder) returned too many results ($($apps.count) matches)"
						}
					} else {
						break
					}
				}
			}
		}
		if (-not $found) {
			$unmatched += $folder
		}
	}
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "... query complete. $($matchTable.Rows.count - $lastMatchedCount) matched ($($matchTable.Rows.count) total), $($unmatched.count) unmatched"
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	
	ForEach ($folder in $unmatched) {
		Write-Log -InputObject "Folder '$($folder)' could not be easily matched$($disclaimer). Adding to sanity check for manual data entry."
		$matchTable.LoadDataRow(@(-1, "????", $folder, $steamLibrary, "Not Matched", $false), $true) | Out-Null
	}
}


$matchTable.EndLoadData()

#endregion

#region Sanity Check
$form = New-SanityCheckForm
$dgv = New-SanityCheckDataGridView -Form $form

$bindingSource = New-Object System.Windows.Forms.BindingSource
$bindingSource.DataSource = $matchTable
$dgv.DataSource = $bindingSource
$dgv.Refresh()

$form.Add_Shown({$Form.Activate()})
$form.Show()

$script:exit = $false
$script:sanityChecked = $false
While (-not $exit)
{
    Start-Sleep -Milliseconds 20
	[System.Windows.Forms.Application]::DoEvents() | Out-Null
}
 
$form.Close()
$form.Dispose()

# $matchTable.Rows | Out-GridView #DEBUG

#endregion

#region Output
if ($sanityChecked -eq $true) {
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "Sanity Check complete - creating app manifests"
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"

	ForEach ($row in $matchTable.Rows) {
		if ($row.Valid -eq $true) {
			if ($row.AppID -eq -1) {
				Write-Log -InputObject "App manifest was not created for '$($row.Folder)' No AppID found for Name '$($row.Name)'$($disclaimer)."
			} 
			elseif ($row.Name -eq "????") {
				Write-Log -InputObject "App manifest was not created for '$($row.Folder)' No Name found for AppID '$($row.AppID)'$($disclaimer)."
			} else {
				New-ACF -AppID $row.AppID -AppName $row.Name -SteamLibrary $row.Library -AppFolder $row.Folder
			}
		}
	}
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"
	Write-Log -InputObject "App Manifests created. Please restart Steam client to validate."
	Write-Log -InputObject "----------------------------------------------------------------------------------------------------"	
}

$appLookup | ConvertTo-Json | Out-File $LookupTablePath -Encoding UTF8

#endregion

Write-LogFooter -InputObject "Script Successful! $($unmatched.count) folders could not be matched - check unmatched.log for a list"