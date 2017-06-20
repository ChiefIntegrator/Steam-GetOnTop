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
        [System.String[]]$InputObject
	)
    process
    {
        $root = New-Object -TypeName PSObject
        $chain = [ordered]@{}
        $depth = 0
        $parent = $root
        $element = $null
		
        ForEach ($line in $InputObject)
        {
            $quotedElements = (Select-String -Pattern '(?<=")([^\"\t\s]+\s?)+(?=")' -InputObject $line -AllMatches).Matches
    
            if ($quotedElements.Count -eq 1) # Create a new (sub) object
            {
                $element = New-Object -TypeName PSObject
                Add-Member -InputObject $parent -MemberType NoteProperty -Name $quotedElements[0].Value -Value $element
            }
            elseif ($quotedElements.Count -eq 2) # Create a new String hash
            {
                Add-Member -InputObject $element -MemberType NoteProperty -Name $quotedElements[0].Value -Value $quotedElements[1].Value
            }
            elseif ($line -match "{")
            {
                $chain.Add($depth, $element)
                $depth++
                $parent = $chain.($depth - 1) # AKA $element
                
            }
            elseif ($line -match "}")
            {
                $depth--
                $parent = $chain.($depth - 1)
				$element = $parent
                $chain.Remove($depth)
            }
            else # Comments etc
            {
            }
        }

        return $root
    }
    
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
		[Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
		[ValidateNotNullOrEmpty()]
		[PSObject]$InputObject,

        [Parameter(Position=1, Mandatory=$false)]
		[int]$Depth = 0
	)
    process
    {
        $output = ""
        
        ForEach ($property in ($InputObject | Get-Member -MemberType NoteProperty) | Where-Object {$_.Definition -match "System.String"})
        {
            $output += ("`t" * $Depth) + "`"" + $property.Name + "`"`t`"" + $InputObject.($property.Name) + "`"`n"
        }
        ForEach ($property in ($InputObject | Get-Member -MemberType NoteProperty) | Where-Object {$_.Definition -match "System.Management.Automation.PSCustomObject"})
        {
            $element = $InputObject.($property.Name)
            $output += ("`t" * $Depth) + "`"" + $property.Name + "`"`n"
            $output += ("`t" * $Depth) + "{`n"
            $Depth++
            $output += ConvertTo-VDF -InputObject $element -Depth $Depth
            $Depth--
            $output +=  ("`t" * $Depth) + "}"
            if ($Depth -gt 0)
            {
                $output += "`n"
            }
        }
    
        return $output
    }
    
}
