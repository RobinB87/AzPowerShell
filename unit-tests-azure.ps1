# File to resemble unit tests.
# Just small functions to quickly test some functionality
function Test-VirtualFilePathCreator()
{
    $paths = "", "archief", "archief/", "archief/bla", "archief/bla/"
    $expected = "", "", "bla/", "bla/"

    $results = @()
    foreach ($path in $paths)
    {
        $targetContainer = ""
        $virtualPathForFileName = ""
		
        if ($path) 
        { 
            # Container is the first folder of the path
            $targetContainer = $path.Split('/')[0]
            $virtualPathForFileName = $path.Replace($targetContainer, "")

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
    
            Write-Host $virtualPathForFileName

            $results += $virtualPathForFileName
        }
    }

    $results
    for ($i = 0; $i -lt $results.Count; $i++)
    {
        Write-Host Result: $($expected[$i] -eq $results[$i])
    }
}

Test-VirtualFilePathCreator