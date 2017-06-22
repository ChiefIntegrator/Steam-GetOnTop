# ---------
# Functions
# ---------
 
Function Set-RowHeaderIndex {
param (
      [Parameter(Mandatory=$true, Position=0)]
      [System.Windows.Forms.DataGridView]$DataGridView
)
      For ($i = 0; $i -lt $DataGridView.Rowcount; $i++) {
            $DataGridView.Rows[$i].HeaderCell.Value = ($i + 1).ToString()
      }
}
# -------
# Include
# -------
 
# Load Forms assemblies
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

Import-Module .\Modules\SteamTools

# ---------
# Main
# ---------
 
#region Create Form
 
# Define Cell Templates
$dgvTextCell = New-Object System.Windows.Forms.DataGridViewTextBoxCell
$dgvTextCell.Style.BackColor = [System.Drawing.Color]::White
 
# Create an empty Form
$Form = New-Object System.Windows.Forms.Form
$Form.width = 400
$Form.height = 600
$Form.Text = "Set Family Sharing Precedence"
$Form.ControlBox = $false
$Form.ShowIcon = $false
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
 
$formWidth = $Form.DisplayRectangle.Width
$formHeight = $Form.DisplayRectangle.Height

$LabelText = New-Object System.Windows.Forms.Label
$LabelText.Location = New-Object System.Drawing.Size(20,20)
$LabelText.Size = New-Object System.Drawing.Size(($formWidth - 40), 60)
$LabelText.Text = "Simply drag and drop to reorder - games owned by users at the top of the list take precedence over those below. Please close Steam before accepting changes. Your existing config file will be backed up as: <steam root>\Config\Config-<date>_<time>.vdf"
$LabelText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$Form.Controls.Add($LabelText)
 
$dgv = New-Object System.Windows.Forms.DataGridView
$dgv.Name = "User List"
$dgv.Location = new-object System.Drawing.Size(20, 100)
$dgv.Size = new-object System.Drawing.Size(($formWidth - 40),($formHeight - 140))
$dgv.MultiSelect = $false
$dgv.AllowUserToAddRows = $false
#$dgv.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells
 
$dgvColumn = New-Object System.Windows.Forms.DataGridViewColumn
$dgvColumn.Name = "ID"
$dgvColumn.HeaderText = "ID"
$dgvColumn.DataPropertyName = "ID"
$dgvColumn.CellTemplate = $dgvTextCell
$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells
$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
$dgvColumn.set_ReadOnly($true)
$dgv.Columns.Add($dgvColumn) | Out-Null
 
$dgvColumn = New-Object System.Windows.Forms.DataGridViewColumn
$dgvColumn.Name = "User"
$dgvColumn.HeaderText = "User Name"
$dgvColumn.DataPropertyName = "User"
$dgvColumn.CellTemplate = $dgvTextCell
$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells
$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
$dgvColumn.set_ReadOnly($true)
$dgv.Columns.Add($dgvColumn) | Out-Null

$dgvColumn = New-Object System.Windows.Forms.DataGridViewColumn
$dgvColumn.Name = "Persona"
$dgvColumn.HeaderText = "Persona Name"
$dgvColumn.DataPropertyName = "Persona"
$dgvColumn.CellTemplate = $dgvTextCell
$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells
$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
$dgvColumn.set_ReadOnly($true)
$dgv.Columns.Add($dgvColumn) | Out-Null

$dgvColumn = New-Object System.Windows.Forms.DataGridViewColumn
$dgvColumn.Name = "Blank"
$dgvColumn.HeaderText = ""
$dgvColumn.CellTemplate = $dgvTextCell
$dgvColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$dgvColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
$dgvColumn.set_ReadOnly($true)
$dgv.Columns.Add($dgvColumn) | Out-Null
 
$dgv.AutoResizeColumns()
$dgv.AutoGenerateColumns = $false
$dgv.AllowDrop = $true
 
 
$script:dragBoxFromMouseDown = [System.Drawing.Rectangle]::Empty
$script:rowIndexFromMouseDown = 0
$script:rowIndexForDrop = 0
 
$dgv.add_CellMouseDown({
	$script:rowIndexFromMouseDown = $_.RowIndex
     
	if ($script:rowIndexFromMouseDown -ne -1) {
		$dragSize = [System.Windows.Forms.SystemInformation]::DragSize
		$script:dragBoxFromMouseDown = New-Object System.Drawing.Rectangle(($_.X - $dragSize.Width / 2), ($_.Y - $dragSize.Height / 2), $dragSize.Width, $dragSize.Height)
    } else {
        $script:dragBoxFromMouseDown = [System.Drawing.Rectangle]::Empty
	}
})
$dgv.add_CellMouseMove({
    if (($_.Button -bAND [System.Windows.Forms.MouseButtons]::Left) -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ( ($script:dragBoxFromMouseDown -ne [System.Drawing.Rectangle]::Empty) -and (-not $script:dragBoxFromMouseDown.Contains($_.X, $_.Y)) ) {
			$dropEffect = $dgv.DoDragDrop($dgv.Rows[$rowIndexFromMouseDown], [System.Windows.Forms.DragDropEffects]::Move)
		}
    }
})
$dgv.add_DragOver({
	$_.Effect = [System.Windows.Forms.DragDropEffects]::Move
})
 
$dgv.add_DragDrop({
	$global:derp = $_
	$clientPoint = $dgv.PointToClient((New-Object System.Drawing.Point($_.X,$_.Y)))
	$script:rowIndexForDrop = $dgv.HitTest($clientPoint.X, $clientPoint.Y).RowIndex;
 
    if ( ($script:rowIndexForDrop -ne -1) -and ($_.Effect -eq [System.Windows.Forms.DragDropEffects]::Move) ) {
		$oldRow = $dgv.Rows[$script:rowIndexFromMouseDown].DataBoundItem.Row
		$newRow = $userTable.NewRow()
		ForEach ( $column in ($oldRow | Get-Member -MemberType Property) ) {
			  $newRow.($column.Name) = $oldRow.($column.Name)
		}
	   
		$userTable.Rows[$script:rowIndexFromMouseDown].Delete()
		$userTable.AcceptChanges()
		$userTable.Rows.InsertAt($newRow, $script:rowIndexForDrop)
	   
		Set-RowHeaderIndex $dgv
    }
})
 
$Form.Controls.Add($dgv) | Out-Null

# Cancel Button
$Button = new-object System.Windows.Forms.Button
$Button.Location = new-object System.Drawing.Size(($formwidth - 108), ($formheight - 32))
$Button.Size = new-object System.Drawing.Size(100,24)
$Button.Text = "Cancel"
$Button.Add_Click({ $script:exit = $true })
$Form.Controls.Add($Button)
$Form.CancelButton = $Button

# Okay Button
$Button = new-object System.Windows.Forms.Button
$Button.Location = new-object System.Drawing.Size(($formwidth - 216), ($formheight - 32))
$Button.Size = new-object System.Drawing.Size(100,24)
$Button.Text = "Accept Changes"
$Button.Add_Click({ $script:commit = $true; $script:exit = $true })
$Form.Controls.Add($Button)
#$Form.AcceptButton = $Button
 
$Form.Add_Shown({$Form.Activate()})
$Form.Show()
 
#endregion
 
#region Create Data Table
 
$userTable = New-Object System.Data.DataTable
$newColumn = $userTable.Columns.Add("ID")
$newColumn.DataType = [System.String]
$newColumn = $userTable.Columns.Add("User")
$newColumn.DataType = [System.String]
$newColumn = $userTable.Columns.Add("Persona")
$newColumn.DataType = [System.String]

$steamPath = Get-SteamPath
$steamConfig = ConvertFrom-VDF (Get-Content "$($steamPath)\Config\Config.vdf")
$steamUsers = ConvertFrom-VDF (Get-Content "$($steamPath)\Config\LoginUsers.vdf")
 
$userTable.BeginLoadData()
ForEach ( $user in ($steamConfig.InstallConfigStore.AuthorizedDevice.PSObject.Members | Where-Object {$_.MemberType -eq "NoteProperty"}) ) {
	$userTable.LoadDataRow(@($user.Name, $steamUsers.users.(Get-SteamID64 $user.Name).AccountName, $steamUsers.users.(Get-SteamID64 $user.Name).PersonaName), $true ) | Out-Null
}
$userTable.EndLoadData()
 
$bindingSource = New-Object System.Windows.Forms.BindingSource
$bindingSource.DataSource = $userTable
$dgv.DataSource = $bindingSource
$dgv.Refresh()
Set-RowHeaderIndex $dgv
 
#endregion
 
$dgv.AutoResizeColumns()
 
$exit = $false
 
While (-not $exit)
{
      Start-Sleep -Milliseconds 50
      [System.Windows.Forms.Application]::DoEvents() | Out-Null
}
 
#$userTable.Rows | Out-GridView
 
$Form.Close()
$Form.Dispose()
 
if ($commit) {
	$oldData = $steamConfig.InstallConfigStore.AuthorizedDevice.psobject.Copy()
	$steamConfig.InstallConfigStore.psobject.Members.Remove("AuthorizedDevice")

	$newData = New-Object -TypeName PSObject
	ForEach ( $row in $userTable.Rows ) {
		Add-Member -InputObject $newData -MemberType NoteProperty -Name $row.ID -Value $oldData.($row.ID)
	}
	
	Add-Member -InputObject $steamConfig.InstallConfigStore -MemberType NoteProperty -Name "AuthorizedDevice" -Value $newData
	
	Copy-Item -Path "$($steamPath)\Config\Config.vdf" -Destination "$($steamPath)\Config\Config-$(Get-Date -Format "yyyyMMdd_hhmmss").vdf"
	ConvertTo-VDF -InputObject $steamConfig | Out-File "$($steamPath)\Config\Config.vdf" -Encoding UTF8
}
