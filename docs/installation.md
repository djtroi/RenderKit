# Install and update RenderKit

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- Access to the PowerShell Gallery
- Write permissions for the selected installation scope

Check the installed PowerShell version:

```powershell
$PSVersionTable.PSVersion
```

## Install from the PowerShell Gallery

### Recommended: PSResourceGet

```powershell
Install-PSResource -Name RenderKit -Scope CurrentUser -Repository PSGallery
Import-Module RenderKit
```

If `Install-PSResource` is not available yet, install PSResourceGet first:

```powershell
Install-Module -Name Microsoft.PowerShell.PSResourceGet -Scope CurrentUser
```

### Alternative: PowerShellGet

```powershell
Install-Module -Name RenderKit -Scope CurrentUser -Repository PSGallery
Import-Module RenderKit
```

If PowerShell prompts you about an untrusted repository, verify the displayed repository name and source before accepting the prompt.

## Install from a local checkout

Clone or extract the repository and import the module manifest directly:

```powershell
Set-Location "C:\Path\To\RenderKit"
Import-Module .\RenderKit.psd1 -Force
```

This method is intended for development and testing. For a permanent manual installation, copy the complete module directory into one of the paths listed in `$env:PSModulePath`.

## Verify the installation

```powershell
Get-Module -ListAvailable -Name RenderKit
Import-Module RenderKit -Force
Get-Command -Module RenderKit
Get-Help Set-ProjectRoot -Full
```

## Update RenderKit

Use the same package manager that was used for the original installation.

### Update with PSResourceGet

```powershell
Update-PSResource -Name RenderKit
Remove-Module RenderKit -ErrorAction SilentlyContinue
Import-Module RenderKit -Force
```

### Update with PowerShellGet

```powershell
Update-Module -Name RenderKit
Remove-Module RenderKit -ErrorAction SilentlyContinue
Import-Module RenderKit -Force
```

For an all-users installation, start PowerShell with the required administrative permissions and update the same installation scope used originally.

## Check installed versions

```powershell
Get-InstalledPSResource -Name RenderKit        # PSResourceGet
Get-InstalledModule -Name RenderKit            # PowerShellGet
Get-Module -ListAvailable -Name RenderKit |
    Sort-Object Version -Descending |
    Select-Object Name, Version, ModuleBase
```

## Reinstall RenderKit

Do not mix package managers for the same installation. Use the commands that match the original installation method.

```powershell
# PSResourceGet
Uninstall-PSResource -Name RenderKit -Scope CurrentUser
Install-PSResource -Name RenderKit -Scope CurrentUser -Repository PSGallery

# PowerShellGet
Uninstall-Module -Name RenderKit -AllVersions
Install-Module -Name RenderKit -Scope CurrentUser -Repository PSGallery
```

After reinstalling, close any PowerShell sessions that still have an older version loaded, or remove and import the module again.

## First project

```powershell
Import-Module RenderKit
New-Item -ItemType Directory -Path "D:\Editing_Projects" -Force
Set-ProjectRoot -Path "D:\Editing_Projects"
New-Project -Name "Demo_2026" -Template "default"
```

## Troubleshooting

- **Command not found:** Check `$env:PSModulePath`, run `Get-Module -ListAvailable RenderKit`, and import the module again.
- **Multiple versions installed:** List every available version and, if necessary, import one explicitly with `Import-Module RenderKit -RequiredVersion <Version>`.
- **Gallery unavailable:** Check proxy and TLS settings, then inspect `Get-PSResourceRepository` or `Get-PSRepository`.
- **Execution policy error:** Inspect `Get-ExecutionPolicy -List`. Change execution policies only according to your organization's requirements.