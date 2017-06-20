function Write-LogHeader { 
	param (
		[Parameter(Position=0, Mandatory=$true)]
		[System.String]$InputObject
	)
	Out-File -FilePath $log -Append -InputObject " "
	Out-File -FilePath $log -Append -InputObject "==========================================================================="
	Out-File -FilePath $log -Append -InputObject ($InputObject)
	Out-File -FilePath $log -Append -InputObject ("Executed : " + (Get-Date -Format "F"))
	Out-File -FilePath $log -Append -InputObject "==========================================================================="
}

function Write-LogFooter {
	param (
		[Parameter(Position=0, Mandatory=$true)]
		[System.String]$InputObject
	)
	Out-File -FilePath $log -Append -InputObject "==========================================================================="
	Out-File -FilePath $log -Append -InputObject ("Execution halted : " + (Get-Date -Format "F"))
	Out-File -FilePath $log -Append -InputObject ("Reason : " + $InputObject)
	Out-File -FilePath $log -Append -InputObject "==========================================================================="
}

function Write-Log {
	param (
		[Parameter(Position=0, Mandatory=$true)]
		[System.String]$InputObject
		,
		[Parameter(Mandatory=$false)]
		[ValidateSet("Error", "Warning", "Standard", "Verbose", "Debug")] 
		[System.String]$MessageLevel = "Standard"
	)
	$symbol = switch ($MessageLevel) {
		"Error" 	{ "!" }
		"Warning"	{ "^" }
		"Standard" 	{ "." }
		"Verbose" 	{ "+" }
		"Debug" 	{ "?" }
	}
	
	switch ($MessageLevel) {
		"Error" 	{$foregroundColour = "Red";						$backgroundColour = "Black"}
		"Warning"   {$foregroundColour = "Yellow";					$backgroundColour = "Black"}
		default 	{$foregroundColour = $defaultForegroundColour;	$backgroundColour = $defaultBackgroundColour}
	}
	if ($MessageLevel -eq "Debug") {
		if ($Level -eq "Debug") {
			Out-File -FilePath $log -Append -InputObject "$(Get-Date -Format "hh:mm:ss tt") [$($symbol)] : $($InputObject)"
			Write-Host $InputObject -ForegroundColor $foregroundColour -BackgroundColor $backgroundColour
		}
	}
	elseif ($MessageLevel -eq "Verbose") {
		if ( ($Level -eq "Debug") -or ($Level -eq "Verbose") ) {
			Out-File -FilePath $log -Append -InputObject "$(Get-Date -Format "hh:mm:ss tt") [$($symbol)] : $($InputObject)"
			Write-Host $InputObject -ForegroundColor $foregroundColour -BackgroundColor $backgroundColour
		}
	} else {
		if ($Level -ne "None") {
			Out-File -FilePath $log -Append -InputObject "$(Get-Date -Format "hh:mm:ss tt") [$($symbol)] : $($InputObject)"
			Write-Host $InputObject -ForegroundColor $foregroundColour -BackgroundColor $backgroundColour
		}
	}
	
}

function Set-LogPath {
	param (
		[Parameter(Position=0, Mandatory=$true)]
		[System.String]$LogPath
	)
	$script:log = $LogPath
}

function Set-LogLevel {
	param (
		[Parameter(Position=0, Mandatory=$true)]
		[ValidateSet("None", "Standard", "Verbose", "Debug")]
		[System.String]$LogLevel
	)
	$script:Level = $LogLevel
}

$defaultForegroundColour = (Get-Host).UI.RawUI.ForegroundColor
$defaultBackgroundColour = (Get-Host).UI.RawUI.BackgroundColor
 