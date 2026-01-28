function Read-ProjectTemplate{

    [CmdletBinding()]
    param(
        [string]$Path #JSON or Markdown
        #[int]maxDepth = 200 #--> Old Windows supports only 260 Length. 
    )

    if (!($Path -or (!(Test-Path $Path)))){
        throw "Template path not found: $Path"
    }
    $ext = [IO.Path]::GetExtension($Path).ToLower()
    $rawFolders = $null

    switch($ext){
        ".json"{
            try{
                $json = Get-Content $Path -Raw | ConvertFrom-Json
                if(!($json.folders)){
                    throw "JSON does not contain a folders tag"
            }
            $rawFolders = $json.folders
        }
        catch{
            throw "Invalid json template: $_"
        }
    }
    ".md"{
        try{
            $lines = Get-Content $Path
            #parse Markdown hiararchy by Leading dashes
            function ParseMarkdown($lines, $level = 1){
                $tree = @()
                foreach ($line in $lines){
                    if ($line -match "^\s*-+\s*(.+)$"){
                        $name = $matches[1].Trim()
                        $tree += @{ Name = $name; Children = @() }
                    }
                }
            return $tree
            }
            $rawFolders = ParseMarkdown $lines
        }
        catch {
            throw "Invalid Markdown template $_"
        }
    }
        
    default{
        throw "unsupported template format: $ext"
    }
    }
}
function Normalize-Folders($folders, $level = 1){
#    if ($level -gt $maxDepth){
#        throw "Folder depth exceeds max depth of $maxDepth"
#    }

$result = @()
foreach ($key in $folders.Keys){
    $child = $folders[$key]
    if ($null -eq $child) { $child = @{} }
    elseif (!($child -is [hashtable])) { throw "folder $key must be a hashtable" }

    $result += @{
        Name = $key 
        Children = Normalize-Folders $child ($level +1)
    }
}
return $result
}

if ($ext -eq ".json"){
    return Normalize-Folders $rawFolders
}
elseif($ext -eq ".md"){
    #Markdown is already created with Name and Children
    return $rawFolders
}

