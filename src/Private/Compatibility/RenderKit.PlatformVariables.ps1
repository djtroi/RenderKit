# PowerShell 6+ exposes $IsWindows as an automatic variable. Windows PowerShell
# 5.1 does not, while RenderKit still supports that host. Define the equivalent
# module-scoped value only when the host does not provide it.
if (-not (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
    $script:IsWindows =
        [System.Environment]::OSVersion.Platform -eq
        [System.PlatformID]::Win32NT
}
