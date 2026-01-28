function Read-ProjectTemplate{

    [CmdletBinding()]
    param(
        [string]$Path #JSON or Markdown
        #[int]maxDepth = 200 #--> #todo to catch max path length limitations while creating structures 
    )

    if (!($Path -or (!(Test-Path $Path)))){
        throw "Template not found: $Path"
    }
    $ext = [IO.Path]::GetExtension($Path).ToLower()

    switch($ext){
        ".json"{
            try{
                $json = Get-Content $Path -Raw | ConvertFrom-Json
                if(!($json.PSObject.Properties['folders'])){
                    throw "JSON does not contain a folders tag"
                    
            }  
            $root = $json.folders
            return Normalize-Folders -Node $root 
        }
        catch{
            throw "Invalid json template: $_"
        }
    }
    ".md"{
        try{
            $lines = Get-Content $Path
            $stack = @(@{})
            $lastIndent = 0

            foreach ($line in $lines) {
                if ($line -notmatch '^\s*-\s+') { continue }

                $indent = ($line -match '^\s*').Length
                $name = ($line -replace '^\s*-\s+', '').Trim()

                while ($indent -lt $lastIndent) {
                    $stack.Pop()
                    $lastIndent -= 2
                }

                $parent = $stack[-1]
                $parent[$name] = @{}

                $stack += $parent[$name]
                $lastIndent = $indent
            }

            $root = $stack[0]
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
function Normalize-Folders {
    param([object]$Node)

    $result = @()

    foreach ($prop in $Node.PSObject.Properties) {
        $children = @()

        # Prüfe, ob $prop.Value ein PSObject ist und nicht null
        if ($prop.Value -and $prop.Value -is [PSCustomObject]) {
            $children = Normalize-Folders -Node $prop.Value
        }

        # Immer ein Array zurückgeben, nie null
        if (-not $children) { $children = @() }

        $folder += [PSCustomObject]@{
            Name     = $prop.Name
            Children = @($children)
        }
        $result += $folder # Wrong Recursive-Array-Handling
    }
#Debug
Write-Host "Returning $($result.Count) folders: $($result | ForEach-Object {$_.Name -join ','})"

    return @($result)  # wichtig: Komma sorgt dafür, dass es als Array interpretiert wird, auch wenn 1 Element
}
$root = json.folders
if ($ext -eq ".json"){
    return Normalize-Folders -Node $root #-Depth 1
}
elseif($ext -eq ".md"){
    #Markdown is already created with Name and Children
    return $rawFolders
}

