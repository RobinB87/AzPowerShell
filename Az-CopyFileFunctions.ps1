# Config file with inputs, to xml
$configPath = $PSScriptRoot
$configPath += "\secrets.config"
$config = ([xml](Get-Content $configPath)).root
$_successMessage = $config.SuccessMessage
$_failureMessage = $config.FailureMessage

# Copy a file synchronously
# .PARAMETER SourcePath The source path. Needs to include the filename and extension, eg: "10y-Archive/rootfiletest.txt"
# .PARAMETER TargetFileShareName The target path. Needs to include the filename and extension, eg: "10y-Archive/rootfiletest.txt"
function CopyFileShareToFileShare($SourceStorageAccountContext, $SourceFileShareName, $SourcePath, $TargetFileShareName, $TargetPath, $TargetStorageAccountContext)
{
    Start-AzStorageFileCopy `
        -Context $SourceStorageAccountContext `
        -SrcShareName $SourceFileShareName `
        -SrcFilePath $SourcePath `
        -DestShareName $TargetFileShareName `
        -DestFilePath $TargetPath `
        -DestContext $TargetStorageAccountContext
}

# Copy a file server side with azcopy.
# .PARAMETER AzSourceDirectory Source directory (uri). Eg. https://sourcestorageaccountname.file.core.windows.net/sharename/foldername
# .PARAMETER AzTargetDirectory Target directory (uri). Eg. https://targetstorageaccountname.file.core.windows.net/targetfolderorcontainername
# .PARAMETER AzCopyPath If AzCopy executable is not in PATH environment variable, enter it's path as parameter
function ServerSideCopyDirectoryRecursive($AzSourceDirectory, $SourceStorageAccountSasToken, $AzTargetDirectory, $TargetStorageAccountSasToken, $AzCopyPath = $null)
{
    $fromUrl = $AzSourceDirectory + $SourceStorageAccountSasToken
    $toUrl = $AzTargetDirectory + $TargetStorageAccountSasToken
    if ($Path)
    {
        Set-Location -Path $Path
    }
    azcopy copy $fromUrl $toUrl --recursive=true
}

# Process all files from a Azure File Share Directory
function MoveAzCloudDirectoriesAndFilesRecursive($AzSourceFileShareName, $AzSourceFileShareDirectory, 
    $SourceStorageAccountContext, $SourceStorageAccountSasToken, $TargetStorageAccount, $TargetStorageAccountSasToken)
{
    Write-Host -ForegroundColor Magenta "Processing directory: " $AzSourceFileShareDirectory.Name
    $targetDirectoryBasePath = $TargetStorageAccount.PrimaryEndpoints.Blob

    # Get path including parent path(s)
    $path = $AzSourceFileShareDirectory.CloudFileDirectory.Uri.PathAndQuery.Remove(0, ($AzSourceFileShareDirectory.CloudFileDirectory.Uri.PathAndQuery.IndexOf('/', 1) + 1))

    $filesOrDirectoriesList = Get-AzStorageFile -ShareName $AzSourceFileShareName -Path $path -Context $SourceStorageAccountContext | Get-AzStorageFile
    foreach ($fileOrDir in $filesOrDirectoriesList)
    {
        $fileName = $fileOrDir.Name
        $pathForDelete = $path + '/' + $fileName
        if ($fileOrDir.GetType().name -eq "AzureStorageFileDirectory")
        {
            # It is a directory; process this 'child'
            MoveAzCloudDirectoriesAndFilesRecursively -AzSourceFileShareName $AzSourceFileShareName -AzSourceFileShareDirectory $fileOrDir `
                -SourceStorageAccountContext $SourceStorageAccountContext -SourceStorageAccountSasToken $SourceStorageAccountSasToken `
                -TargetStorageAccount $TargetStorageAccount -TargetStorageAccountSasToken $TargetStorageAccountSasToken

            # Delete directory (it's content is already processed at this point)
            Remove-AzStorageDirectory -ShareName $AzSourceFileShareName -Path $pathForDelete -Context $SourceStorageAccountContext
        }
        elseif ($fileOrDir.GetType().name -eq "AzureStorageFile")
        {
            # It is a file; copy to target path and delete source 
            Write-Host -ForegroundColor Green "Processing file: " $fileName
            
            $sourcePathWithSasToken = $AzSourceFileShareDirectory.CloudFileDirectory.Uri.AbsoluteUri + '/' + $fileName + $SourceStorageAccountSasToken
            $targetPathWithSasToken = $targetDirectoryBasePath + $path.ToLower() + '/' + $fileName + $TargetStorageAccountSasToken
            $resultLog = AzCopy copy $sourcePathWithSasToken $targetPathWithSasToken

            # Check result log
            $result = $resultLog | Where-Object { $_ -eq $success -or $failure }
            if ($result -eq $_successMessage)
            {
                Remove-AzStorageFile -ShareName $AzSourceFileShareName -Path $pathForDelete -Context $SourceStorageAccountContext
            } 
            elseif ($result -eq $_failureMessage)
            {
                Write-Host -ForegroundColor Red "Kopiëren bestand " $fileName "is mislukt."
                # TODO: Log
            }
        }
        else
        {
            Write-Host -ForegroundColor Red "Filetype: " $fileOrDir.GetType().name " is nog niet geïmplementeerd."
            # TODO: Log
        }
    }
}