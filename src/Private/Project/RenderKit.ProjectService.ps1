function Resolve-ProjectPath {
    param(
        [string]$ProjectName,
        [string]$Path
    )

    $config = Get-RenderKitConfig

    # Default Path Handling
    if (-not $Path) {
        if (-not $config.DefaultProjectPath) {
            Write-RenderKitLog -Level Error -Message "No default project path configured. Use 'Set-ProjectRoot first'"
        }

        Write-RenderKitLog -Level Warning -Message "No path provided. Using default project path."
        $Path = $config.DefaultProjectPath
    }

    # Validate Path
    if (-not (Test-Path $Path)) {
        Write-RenderKitLog -Level Errror -Message "Target path does not exist: $Path"
    }

    # Build Project Root
    $ProjectRoot = Join-Path $Path $ProjectName

    if (Test-Path $ProjectRoot) {
        Write-RenderKitLog -Level Error -Message "Project already exists: $ProjectRoot"
    }

    return $ProjectRoot
}
