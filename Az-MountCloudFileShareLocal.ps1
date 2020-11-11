# Mount a cloud file share: on premise
function MountDrive($OnPremiseDriveLetter, $OnPremiseDrivePath, $FileShareEndpoint, $FileShareName, $FileShareKey)
{
    $mappedDrive = (Get-PSDrive -Name $OnPremiseDriveLetter -ErrorAction SilentlyContinue)
    $connectTestResult = Test-NetConnection -ComputerName $FileShareEndpoint -Port 445
    if (!($connectTestResult.TcpTestSucceeded))
    {
        Write-Error -Message "Unable to reach the Azure storage account via port 445. Check to make sure your organization or ISP is not blocking port 445, or use Azure P2S VPN, Azure S2S VPN, or Express Route to tunnel SMB traffic over a different port."
    }
    elseif (!($mappedDrive))
    {
        # Save the password so the drive will persist on reboot
        cmd.exe /C "cmdkey /add:`"$FileShareEndpoint`" /user:`"Azure\$FileShareName`" /pass:`"$FileShareKey`""
        # Mount the drive
        New-PSDrive -Name Z -PSProvider FileSystem -Root $OnPremiseDrivePath -Persist
    }
}

function SetMountedLocation($OnPremiseDrivePath, $Directory)
{
    if (!($OnPremiseDrivePath -match '\\$')) 
    {
        $OnPremiseDrivePath += "\"
    }
    Set-Location -Path $OnPremiseDrivePath + $Directory
}