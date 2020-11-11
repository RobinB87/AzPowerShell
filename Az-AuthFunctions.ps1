# Set the Azure authentication context and store in file
# .PARAMETER ContextFilePath The json file path where the context should be saved
function StoreAuthenticationContext($ContextFilePath)
{
    $authContext = $null
    if (Test-Path $ContextFilePath)
    {
        # If context file exists, import it
        $authContext = Import-AzContext -Path $ContextFilePath
    }
    if (!$authContext)
    {
        # if context file not exists, or auth file is corrupt, authenticate
        $authContext = Save-AzContext -Profile (Connect-AzAccount) -Path $ContextFilePath
    }
}

# Create a (source or target) storage account sas token.
# .PARAMETER ServiceType The service type, e.g.: Blob (Blob Storage) or File (FileShare). Can be multiple, e.g.: Blob, File
# .PARAMETER ResourceType The resource type, e.g.: Container (e.g. copy a container), File (e.g. copy a file share), Object (e.g. copy a file/blob). Can be multiple, e.g.: Blob, File
# .PARAMETER ResourceType The permission, e.g.: 'rwdlacup' (read, write, delete, etc...)
# .PARAMETER AddHours Extend the length of the expirytime with additional hours
function CreateStorageAccountSasToken($StorageAccountContext, $ServiceType, $ResourceType, $Permission, $AddHours = 0)
{
    # Create SAS token with Blob (Blob Storage) and Object (a file) parameters
    return New-AzStorageAccountSASToken -Context $StorageAccountContext -Service $ServiceType `
        -ResourceType $ResourceType -Permission $Permission -ExpiryTime (Get-Date).AddHours($AddHours)
}