<#
.SYNOPSIS
Adds a media type definition to a mapping.

.DESCRIPTION
Loads a mapping file and appends a type entry with name and file extensions.

.PARAMETER MappingId
Mapping id to update (with or without `.json` extension).

.PARAMETER TypeName
Logical type name stored in the mapping (for example `Video`, `Audio`, `Proxy`).

.PARAMETER Extensions
One or more file extensions assigned to the type.
Use values like `.mp4`, `.mov`, `.wav` for best results.

.EXAMPLE
Add-RenderKitTypeToMapping -MappingId "camera" -TypeName "Video" -Extensions ".mp4",".mov"
Adds a `Video` type with extensions `.mp4` and `.mov`.

.EXAMPLE
Add-RenderKitTypeToMapping -MappingId "audio" -TypeName "Sound" -Extensions ".wav",".aif",".mp3"
Adds a `Sound` type with common audio extensions.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
None. The command updates the mapping file on disk.

.LINK
New-RenderKitMapping

.LINK
Add-RenderKitMappingToTemplate

.LINK
https://github.com/djtroi/RenderKit
#>
function Add-RenderKitTypeToMapping {
    param(
        [string]$MappingId,
        [string]$TypeName,
        [string[]]$Extensions # TODO: Validate and structure extensions
    )

    Write-RenderKitLog -Level Debug -Message "Add-RenderKitTypeToMapping started: MappingId='$MappingId', TypeName='$TypeName', ExtensionCount=$(@($Extensions).Count)."

    $mappingPath = Get-RenderKitUserMappingPath -MappingId $MappingId
    if (!(Test-Path $mappingPath)) {
        Write-RenderKitLog -Level Error -Message "Mapping $MappingId not found"
    }

    $json = Read-RenderKitMappingFile -MappingId $MappingId

    if (-not ($json.PSObject.Properties.Name -contains "Types")) {
        $json | Add-Member -MemberType NoteProperty -Name Types -Value ([System.Collections.ArrayList]::new()) -Force
    }
    elseif ($json.Types -isnot [System.Collections.ArrayList]) {
        $json.Types = [System.Collections.ArrayList]@($json.Types)
    }

    $null = $json.Types.Add(@{
        Name        =   $TypeName
        Extensions  =   $Extensions
    })

    Write-RenderKitMappingFile -Mapping $json -MappingId $MappingId
    Write-RenderKitLog -Level Info -Message "Type ""$TypeName"" added to $MappingId."
}
