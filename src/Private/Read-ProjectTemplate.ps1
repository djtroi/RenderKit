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
            return Normalize-Folders -Node $json.folders 
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
                    $stack = $stack[0..($stack.Count - 2)]
                    $lastIndent -= 2
                }

                $parent = $stack[-1]
                $parent[$name] = @{}

                $stack += $parent[$name]
                $lastIndent = $indent
            }

            return Normalize-Folders -Node $root
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

    param(
        [Parameter(Mandatory)]
        [object]$Node
    )

    $result = @()

    # Hashtable (Markdown)
    if ($Node -is [hashtable]) {

        foreach ($key in $Node.Keys) {

            $children = @()

            if (
                $Node[$key] -and
                $Node[$key] -is [hashtable] -and
                $Node[$key].Count -gt 0
            ) {
                $children = Normalize-Folders -Node $Node[$key]
            }

            $result += [PSCustomObject]@{
                Name     = $key
                Children =  @($children)
            }
        }
    }

    # PSCustomObject (JSON)
    elseif ($Node -is [PSCustomObject]) {

        foreach ($prop in $Node.PSObject.Properties) {

            $children = @()

            if (
                $prop.Value -and
                (
                    $prop.Value -is [hashtable] -or
                    $prop.Value -is [PSCustomObject]
                ) -and
                $prop.Value.PSObject.Properties.Count -gt 0
            ) {
                $children = Normalize-Folders -Node $prop.Value
            }

            $result += [PSCustomObject]@{
                Name     = $prop.Name
                Children = $children
            }
        }
    }

    return @($result)
}
    


