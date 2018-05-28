Function ConvertFrom-VDF {
<# 
.Synopsis 
    Reads a Valve Data File (VDF) formatted string into a custom object.

.Description 
    The ConvertFrom-VDF cmdlet converts a VDF-formatted string to a custom object (PSCustomObject) that has a property for each field in the VDF string. VDF is used as a textual data format for Valve software applications, such as Steam.

.Parameter InputObject
    Specifies the VDF strings to convert to PSObjects. Enter a variable that contains the string, or type a command or expression that gets the string. 

.Example 
    $vdf = ConvertFrom-VDF -InputObject (Get-Content ".\SharedConfig.vdf")

    Description 
    ----------- 
    Gets the content of a VDF file named "SharedConfig.vdf" in the current location and converts it to a PSObject named $vdf

.Inputs 
    System.String

.Outputs 
    PSCustomObject


#>
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $InputObject
    )

    $root = New-Object -TypeName PSObject
    $chain = [ordered]@{}
    $depth = 0
    $parent = $root
    $element = $null

    #Magic PowerShell Switch Enumrates Arrays
    switch -Regex ($InputObject) {
        #Case: ValueKey
        '^\t*"(\S+)"\t\t"(.+)"$' {
            Add-Member -InputObject $element -MemberType NoteProperty -Name $Matches[1] -Value $Matches[2]
            continue
        }
        #Case: ParentKey
        '^\t*"(\S+)"$' { 
            $element = New-Object -TypeName PSObject
            Add-Member -InputObject $parent -MemberType NoteProperty -Name $Matches[1] -Value $element
            continue
        }
        #Case: Opening ParentKey Scope
        '^\t*{$' {
            $parent = $element
            $chain.Add($depth, $element)
            $depth++
            continue
        }
        #Case: Closing ParentKey Scope
        '^\t*}$' {
            $depth--
            $parent = $chain.($depth - 1)
            $element = $parent
            $chain.Remove($depth)
            continue
        }
        #Case: Comments or unsupported lines
        Default {
            Write-Debug "Ignored line: $_"
            continue
        }
    }

    return $root
}

Function ConvertTo-VDF
{
<# 
.Synopsis 
    Converts a custom object into a Valve Data File (VDF) formatted string.

.Description 
    The ConvertTo-VDF cmdlet converts any object to a string in Valve Data File (VDF) format. The properties are converted to field names, the field values are converted to property values, and the methods are removed.

.Parameter InputObject
    Specifies PSObject to be converted into VDF strings.  Enter a variable that contains the object. You can also pipe an object to ConvertTo-Json.

.Example 
    ConvertTo-VDF -InputObject $VDFObject | Out-File ".\SharedConfig.vdf"

    Description 
    ----------- 
    Converts the PS object to VDF format and pipes it into "SharedConfig.vdf" in the current directory

.Inputs 
    PSCustomObject

.Outputs 
    System.String


#>
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [PSObject]
        $InputObject,

        [Parameter(Position=1, Mandatory=$false)]
        [int]
        $Depth = 0
    )
    $output = [string]::Empty
    
    foreach ( $property in ($InputObject.psobject.Properties) ) {
        switch ($property.TypeNameOfValue) {
            "System.String" { 
                $output += ("`t" * $Depth) + "`"" + $property.Name + "`"`t`t`"" + $property.Value + "`"`n"
                break
            }
            "System.Management.Automation.PSCustomObject" {
                $element = $property.Value
                $output += ("`t" * $Depth) + "`"" + $property.Name + "`"`n"
                $output += ("`t" * $Depth) + "{`n"
                $output += ConvertTo-VDF -InputObject $element -Depth ($Depth + 1)
                $output += ("`t" * $Depth) + "}`n"
                break
            }
            Default {
                Write-Error ("Unsupported Property of type {0}" -f $_) -ErrorAction Stop
                break
            }
        }
    }

    return $output
}

Function Get-SteamPath {
	return (Get-Item HKCU:\Software\Valve\Steam\).GetValue("SteamPath").Replace("/","\")
}

Function Get-SteamID64 {
param(
	[Parameter(Position=0, Mandatory=$true)]
	[int]$SteamID3
)
	if (($SteamID3 % 2) -eq 0) {
		$Y = 0;
		$Z = ($SteamID3 / 2);
	} else {
		$Y = 1;
		$Z = (($SteamID3 - 1) / 2);
	}

	return "7656119$(($Z * 2) + (7960265728 + $Y))"
}