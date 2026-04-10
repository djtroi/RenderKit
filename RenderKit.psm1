# Module Version
    # Paths
    $srcPath     = Join-Path $PSScriptRoot 'src'
    $publicPath  = Join-Path $srcPath 'Public'
    $privatePath = Join-Path $srcPath 'Private'
    $classesPath = Join-Path $srcPath 'Classes'

    #define module paths
    $script:ManifestPath = Join-Path $PSScriptRoot 'RenderKit.psd1'
    $script:RenderKitModuleRoot = $PSScriptRoot

    #Version
    if (Test-Path $script:ManifestPath) {
        $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        $script:RenderKitModuleVersion = $manifest.ModuleVersion
    }
    else {
        $script:RenderKitModuleVersion = '0.0.0-unknown'
    }

    # Bootstrap Logging
    $script:RenderKitLoggingInitialized = $false
    $script:RenderKitBootstrapLog = New-Object System.Collections.Generic.List[string]
    $script:RenderKitDebugMode = $false

    #Snaphot
    $before = (Get-Command -CommandType Function).Name

    #PRIVATE
    if (Test-Path $privatePath) {
        Get-ChildItem $privatePath -Recurse -Filter *.ps1 | ForEach-Object { . $_.FullName }
    }

    #CLASSES
    if (Test-Path $classesPath) {
        Get-ChildItem $classesPath -Recurse -Filter *.ps1 | ForEach-Object { . $_.FullName }
    }

    #PUBLIC
    $PublicFunctions = @()

    if (Test-Path $publicPath) {
        Get-ChildItem $publicPath -Recurse -Filter *.ps1 | ForEach-Object { . $_.FullName }

        foreach ($file in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $funcs = $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $true)

            foreach ($f in $funcs) {
                $PublicFunctions += $f.Name
            }

            . $file.FullName
        }
    }

    $after = (Get-Command -CommandType Function).Name

    #Snapshot after 
    $after = (Get-Command -CommandType Function).Name
    $PublicFunctions = $after | Where-Object { $_ -notin $before }

    #EXPORT
    if ($PublicFunctions.Count -gt 0) {
        Export-ModuleMember -Function $PublicFunctions
    }

    

