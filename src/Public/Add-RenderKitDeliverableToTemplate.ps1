Register-RenderKitFunction "Add-RenderKitDeliverableToTemplate"
function Add-RenderKitDeliverableToTemplate {
    <#
.SYNOPSIS
Adds or updates a deliverable definition in a user template.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$TemplateName,
        [Parameter(Mandatory, Position = 1)]
        [string]$Id,
        [string]$Name,
        [Parameter(Mandatory)]
        [string[]]$SourceFolder,
        [switch]$Recursive,
        [string[]]$MappingId,
        [string[]]$TypeName,
        [string[]]$IncludeExtension,
        [string[]]$ExcludePattern,
        [switch]$DefaultPackage
    )

    Write-RenderKitLog -Level Debug -Message "Add-RenderKitDeliverableToTemplate started: Template='$TemplateName', Id='$Id'."

    $templatePath = Get-RenderKitUserTemplatePath -TemplateName $TemplateName
    if (!(Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        Write-RenderKitLog -Level Error -Message "Template '$TemplateName' not found."
        throw "Template '$TemplateName' not found."
    }

    $template = Read-RenderKitTemplateFile -Path $templatePath
    if ($template.PSObject.Properties.Name -contains "Version") {
        $template.Version = "1.1"
    }
    else {
        $template | Add-Member -MemberType NoteProperty -Name Version -Value "1.1" -Force
    }

    if (-not ($template.PSObject.Properties.Name -contains "Deliverables")) {
        $template | Add-Member -MemberType NoteProperty -Name Deliverables -Value ([System.Collections.ArrayList]::new()) -Force
    }
    elseif ($template.Deliverables -isnot [System.Collections.ArrayList]) {
        $template.Deliverables = [System.Collections.ArrayList]@($template.Deliverables)
    }

    $normalizedExtensions = @($IncludeExtension | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $value = $_.Trim().ToLowerInvariant()
        if ($value.StartsWith('.')) { $value } else { ".$value" }
    })

    $deliverable = [PSCustomObject]@{
        Id                = $Id
        Name              = $(if ([string]::IsNullOrWhiteSpace($Name)) { $Id } else { $Name })
        SourceFolders     = @($SourceFolder)
        Recursive         = [bool]$Recursive
        MappingIds        = @($MappingId)
        TypeNames         = @($TypeName)
        IncludeExtensions = @($normalizedExtensions)
        ExcludePatterns   = @($ExcludePattern)
        DefaultPackage    = [bool]$DefaultPackage
    }

    $existing = @($template.Deliverables | Where-Object { $_.Id -eq $Id }) | Select-Object -First 1
    if ($existing) {
        if ($PSCmdlet.ShouldProcess($TemplateName, "Update deliverable '$Id'")) {
            $index = $template.Deliverables.IndexOf($existing)
            $template.Deliverables[$index] = $deliverable
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess($TemplateName, "Add deliverable '$Id'")) {
            $null = $template.Deliverables.Add($deliverable)
        }
    }

    Write-RenderKitTemplateFile -Template $template -Path $templatePath
    Write-RenderKitLog -Level Info -Message "Deliverable '$Id' saved in template '$TemplateName'."
}