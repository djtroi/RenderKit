function Read-ProjectTemplate{

    [CmdletBinding()]
    param(
        [string]$Path #JSON or Markdown
        
    )

    if (-not $Path -or -not (Test-Path $Path)) {
        throw "Template not found: $Path"
    }
    $ext = [IO.Path]::GetExtension($Path).ToLower()

    switch($ext){
        ".json" {
            try {
                $json = Get-Content $Path -Raw | ConvertFrom-Json -ErrorAction Stop
                if (-not ($json.PSObject.Properties['Folders'])) {
                    throw "JSON does not contain a folders tag"
                }
                return Format-Folders -Node $json.folders
            }
            catch {
                throw "Invalid json template: $_"
            }
        }
        ".md" {
            try {
                $lines = Get-Content $Path
                $stack = @(@{})
                $lastIndent = 0

            foreach ($line in $lines) {
                if ($line -notmatch '^\s*-\s+') { continue }

                $indent = ($line -match '^\s*').Length
                $name = ($line -replace '^\s*-\s+', '').Trim()

                while ($indent -lt $lastIndent) {
                    $stack = $stack[0..($stack.Count - 2)]
                    $lastIndent -= 2
                }

                $parent = $stack[-1]
                $parent[$name] = @{}

                $stack += $parent[$name]
                $lastIndent = $indent
            }

            $root = $stack[0]
            return Format-Folders -Node $root
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
function Format-Folders {

    param(
        [Parameter(Mandatory)]
        [object]$Node
    )

    $result = @()

    if ($Node -is [System.Collections.IEnumerable] -and 
    $Node -isnot [string] -and 
    $Node -isnot [hashtable]) {
        foreach ($item in $Node) {
            $children = @()

            if($item.SubFolders -and $item.SubFolders.Count -gt 0 ) {
                 $children = Format-Folders -Node $item.SubFolders
            }

            $result += [PSCustomObject]@{
                Name        =   $item.Name
                Children    =   @($children)
            }
        }
    }

    elseif ($Node -is [hashtable]) {
        foreach ($key in $Node.Keys){
            $children = @()
            
            if($Node[$key] -and $Node[$key].Count -gt 0 ) {
                $children = Format-Folders -Node $Node[$key]
            }

            $result += [PSCustomObject]@{
                Name        =   $key
                Children    =   @($children)
            }
        }
    }

    return @($result)
}
    
