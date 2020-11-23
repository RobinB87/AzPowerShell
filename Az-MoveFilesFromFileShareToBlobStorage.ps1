# Config file with inputs, to xml
$configPath = $PSScriptRoot
$configPath += "\secrets.config"
$config = ([xml](Get-Content $configPath)).root

# Input variables for local Az Connection
$_contextFilePath = $config.ContextFilePath
$_subscriptionName = $config.SubscriptionName

# Input variables required for copy
$_coldStorageSourceFolderName = $config.ColdStorageSourceFolderName
$_archiveStorageSourceFolderName = $config.ArchiveStorageSourceFolderName
$_coldStorageTargetFolderName = $config.ColdStorageTargetFolderName
$_archiveStorageTargetFolderName = $config.ArchiveStorageTargetFolderName

# Connect to Azure Account
$authContext = $null
if (Test-Path $_contextFilePath)
{
    # If context file exists, import it
    $authContext = Import-AzContext -Path $_contextFilePath
}
if (!$authContext)
{
    # if context file not exists, or auth file is corrupt, authenticate and store
    $authContext = Save-AzContext -Profile (Connect-AzAccount) -Path $_contextFilePath
}

# Set correct subscription
Get-AzSubscription -SubscriptionName $_subscriptionName | Set-AzContext

# Create a (source or target) storage account sas token.
# .PARAMETER ServiceType The service type, e.g.: Blob (Blob Storage) or File (FileShare). Can be multiple, e.g.: Blob, File
# .PARAMETER ResourceType The resource type, e.g.: Container (e.g. copy a container), File (e.g. copy a file share), Object (e.g. copy a file/blob). Can be multiple, e.g.: Blob, File
# .PARAMETER ResourceType The permission, e.g.: 'rwdlacup' (read, write, delete, etc...)
# .PARAMETER AddHours Extend the length of the expirytime with additional hours
function CreateStorageAccountSasToken($StorageAccountContext, $ServiceType, $ResourceType, $Permission, $AddHours = 0)
{
    # Create SAS token with Blob (Blob Storage) and Object (a file) parameters
    $sasToken = New-AzStorageAccountSASToken -Context $StorageAccountContext -Service $ServiceType `
        -ResourceType $ResourceType -Permission $Permission -ExpiryTime (Get-Date).AddHours($AddHours)

    if (!($sasToken))
    {
        Write-Output -ForegroundColor Red "Aanmaken SAS token mislukt voor storage account: " $StorageAccountContext.StorageAccountName
        exit
    }

    return $sasToken
}

function CreateVirtualPath($Path)
{
    $virtualPathForFileName = $Path.Replace($targetContainer, "")
    if ($virtualPathForFileName.StartsWith('/'))
    {
        # Remove the leading slash
        $virtualPathForFileName = $virtualPathForFileName.SubString(1)
    }

    if ($virtualPathForFileName -and !($virtualPathForFileName).EndsWith('/'))
    {   
        # Add trailing slash
        $virtualPathForFileName += '/'
    }

    return $virtualPathForFileName
}

# Process all files from a Azure File Share Directory
function MoveAzCloudDirectoriesAndFilesRecursively($AzSourceFileShareName, $AzSourceFileShareDirectory, 
    $SourceStorageAccountContext, $SourceStorageAccountSasToken, $TargetStorageAccount, $TargetStorageAccountSasToken)
{
    Write-Output -ForegroundColor Magenta "Processing directory: " $AzSourceFileShareDirectory.Name

    # Get path including parent path(s)
    $path = $AzSourceFileShareDirectory.CloudFileDirectory.Uri.PathAndQuery.Remove(0, ($AzSourceFileShareDirectory.CloudFileDirectory.Uri.PathAndQuery.IndexOf('/', 1) + 1))
    $targetContainer = ""
    $virtualPathForFileName = ""
    if ($path) 
    { 
        # Container is the first folder of the path
        $targetContainer = $path.Split('/')[0]
        $virtualPathForFileName = CreateVirtualPath -Path $path
        
        # Now make container lowercase, as containers can only be lower case and it is not used in codeblock below anymore
        $targetContainer = $targetContainer.ToLower()
    }

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
            Write-Output -ForegroundColor Green "Processing file: " $fileName

            $virtualDirectoryAndFile = $virtualPathForFileName + $fileName
            # Copy the file
            $targetSaContextWithSasToken = New-AzStorageContext -StorageAccountName $TargetStorageAccount.StorageAccountName -SasToken $TargetStorageAccountSasToken
            Start-AzStorageBlobCopy `
                -Context $SourceStorageAccountContext `
                -SrcShareName $AzSourceFileShareName `
                -SrcFilePath $pathForDelete `
                -DestContext $targetSaContextWithSasToken `
                -DestContainer $targetContainer `
                -DestBlob $virtualDirectoryAndFile `
                -Force

            # Check if status not empty and if succes
            $copyStatus = Get-AzStorageBlobCopyState -Blob $virtualDirectoryAndFile -Container $targetContainer -Context $targetSaContextWithSasToken -WaitForComplete
            if ($copyStatus -and $copyStatus.Status -eq "Success")
            {
                # Delete delete it at source
                Remove-AzStorageFile -ShareName $AzSourceFileShareName -Path $pathForDelete -Context $SourceStorageAccountContext
            }
            else
            {
                Write-Output -ForegroundColor Red "Kopieren bestand" $fileName "is mislukt."
                # Retry?
                exit
            }
        }
        else
        {
            Write-Output -ForegroundColor Red "Filetype: " $fileOrDir.GetType().name " is nog niet in gebruik."
        }
    }
}

$resourceGroupList = Get-AzResourceGroup -Name *FileSync*
foreach ($rg in $resourceGroupList)
{
    $rgName = $rg.ResourceGroupName
    $storageSyncServiceList = Get-AzStorageSyncService -ResourceGroupName $rgName

    foreach ($storageSyncService in $storageSyncServiceList)
    {
        $storageSyncServiceName = $storageSyncService.StorageSyncServiceName 
        $storageSyncGroupList = Get-AzStorageSyncGroup -ResourceGroupName $rgName -StorageSyncServiceName $storageSyncServiceName

        foreach ($storageSyncGroup in $storageSyncGroupList)
        {
            $syncGroupName = $storageSyncGroup.SyncGroupName
            $storageSyncCloudEndpointList = Get-AzStorageSyncCloudEndpoint -ResourceGroupName $rgName `
                -StorageSyncServiceName $storageSyncServiceName -SyncGroupName $syncGroupName

            foreach ($storageSyncCloudEndpoint in $storageSyncCloudEndpointList)
            {
                $azSourceFileShareName = $storageSyncCloudEndpoint.AzureFileShareName
                $storageAccountList = Get-AzStorageAccount

                foreach ($sa in $storageAccountList)
                {
                    if (! ($sa.Id -eq $storageSyncCloudEndpoint.StorageAccountResourceId))
                    {
                        continue
                    }

                    $sourceSaContext = (Get-AzStorageAccount -ResourceGroupName $rgName -Name $sa.StorageAccountName).Context

                    # Create SAS token with File (File Share) and Object (a file) parameters
                    $sourceSaSasToken = CreateStorageAccountSasToken -StorageAccountContext $sourceSaContext -ServiceType "File" `
                        -ResourceType "Object" -Permission "rwdlacup" -AddHours 12

                    $azSourceFileShareDirectoryList = Get-AzStorageFile -ShareName $azSourceFileShareName -Context $sourceSaContext
                    foreach ($directory in $azSourceFileShareDirectoryList)
                    {
                        $directoryName = $directory.Name
                        $targetStorageAccount;
                         
                        # Get target storage account from the list of storage accounts
                        if ($directoryName -eq $_coldStorageSourceFolderName)
                        { 
                            $targetStorageAccount = $storageAccountList | Where-Object { $_.StorageAccountName -eq $_coldStorageTargetFolderName }
                        }
                        elseif ($directoryName -eq $_archiveStorageSourceFolderName)
                        {
                            $targetStorageAccount = $storageAccountList | Where-Object { $_.StorageAccountName -eq $_archiveStorageTargetFolderName }
                        }
                        else
                        {
                            continue
                        }

                        $targetSaContext = (Get-AzStorageAccount -ResourceGroupName $rgName -Name $targetStorageAccount.StorageAccountName).Context

                        # Create SAS token with Blob (Blob Storage) and Object (a file) parameters
                        $targetSaSasToken = CreateStorageAccountSasToken -StorageAccountContext $targetSaContext -ServiceType "Blob" `
                            -ResourceType "Container, Object" -Permission "rwdlacup" -AddHours 12
                            
                        MoveAzCloudDirectoriesAndFilesRecursively -AzSourceFileShareName $azSourceFileShareName -AzSourceFileShareDirectory $directory `
                            -SourceStorageAccountContext $sourceSaContext `
                            -SourceStorageAccountSasToken $sourceSaSasToken `
                            -TargetStorageAccount $targetStorageAccount -TargetStorageAccountSasToken $targetSaSasToken
                    }
                        
                    break
                }
            }
        }
    }
}