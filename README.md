# Steam... Get on top!

## SUMMARY
	
	This is a suite of PowerShell scripts to get on top of the burden of managing an unwieldy Steam library. Presently, it consists of:
	
		- VDFTools module: Adds ConvertTo-VDF and ConvertFrom-VDF functions to powershell, to parse Valve Data Files into usable data objects.
		- Publish-SteamAppManifests: Scans install folders in <steam>\SteamApps\Common and creates missing App Manifests. Greatly simplifies library migration/recovery!
		- Initialize-SteamAppLookup: Builds a JSON data file containing a lookup table that allows correlation of Steam AppIDs, Names and Install directories - not hugely useful, but speeds up Publish-SteamAppManifests!

## REQUIREMENTS

	Powershell 3.0
	.NET Framework
	Steam
	Internet connection (to grab AppIDs and Names directly from Steam)

## USAGE GUIDE

###	Getting Started
	
		- Copy the files and subfolders in this directory to a sensible location on your local computer. For the sake of this guide, let's copy to 'C:\Scripts\Steam-GetOnTop'.
		- Run PowerShell
		- Set the location to where ever you copied the files. eg: Set-Location "C:\Scripts\Steam-GetOnTop" (cd "C:\Scripts\Steam-GetOnTop" will work too)
		- Exit Steam
		- Run .\Publish-SteamAppManifests.ps1 (Run Get-Help .\Publish-SteamAppManifests.ps1 for details on command line parameters)
		- Watch the logging test scroll by
		- When the 'Sanity Check' window pops up, look through each row and confirm that a sensible match has been made:
			+ Ensure the 'Valid?' checkbox is ticked for each app you'd like to create a manifest for
			+ Uncheck the 'Valid?' checkbox for anything you don't want a manifest for - install directories remain after an app has been uninstalled, and some matches may not be quite accurate
			+ AppID and Name columns are editable and will validate against Steam - if a false match is made, you can readily correct this
		- If you're happy, click "Build ACFs"
		- Restart Steam, and it will now validate all new app manifests. This may take some time, but it will run in the background (go to Steam -> Library -> Downloads to see the validation queue)

###	How It Works
	
		- Check registry for Steam root path
		- Check <steam root>\config\config.vdf for additional libraries
		- Download a complete list of Steam apps from http://api.steampowered.com/ISteamApps/GetAppList/v0001/
		- Load a lookup table that contains AppIDs, Names and Install Directories (default: .\AppLookup.json)
		- Get local steam users from <steam root>\userdata
		- Get a full list of that user's games from http://steamcommunity.com/profiles/<userID>/games?tab=all&xml=1 (by default the script will only match against your owned games)
		- For each install directory in <steam root>\SteamApps\Common\:
			+ Try to match against lookup table (fastest, most accurate)
			+ Try to find app named identically to the install directory name (fast, accurate)
			+ Try a regex match of the install directory name (prone to finding multiple results, for instance "Game Title" may match "Game Title", "Game Title Trailer", "Game Title Demo", etc)
			+ Try a regex match with each word in the install directory name (space delimited) (more robust than above, but less accurate)
			+ Try a regex match with each word in the install directory name where no spaces are present (for instance "ThisSteamGame" will try to match "This" and "Steam" and "Game")
			+ Try a regex match with each word in the install directory name (underscore delimited)
		- With the data scraped by the queries above a table will be populated, and any unmatched install directories will be tacked on for manual intevention
		- User is presented with a "Sanity Check" window that tabulates all results.
		- User can mark each row as valid or not, and add/edit AppIDs and Names for bad matches or unmatched directories
		- With the user's consent, app manifests will be created in the appropriate location
			+ App manifests are created with only an AppID, Name, InstallDir and a StateFlag of 2 (StateUpdateRequired). This is essentially the same as clicking "Install" in the Steam client. - Steam will populate all other data, and check for existing files.
		- Authoritative matches (where an ACF exists already) are added to the lookup table 