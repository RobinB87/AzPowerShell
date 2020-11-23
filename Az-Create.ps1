# Get automation account name
Get-AzAutomationAccount -ResourceGroupName $RgName

# Create Automation Powershell Runbook
New-AzAutomationRunbook -AutomationAccountName $AutomationAccountName `
    -Name $Name -ResourceGroupName $RgName -Type PowerShell