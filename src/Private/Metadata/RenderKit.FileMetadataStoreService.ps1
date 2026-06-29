function ConvertTo-RenderKitSha256Text {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha256.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
    }
}

function Test-RenderKitPathInsideRoot {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $rootWithSeparator = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith(
        $rootWithSeparator,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Get-RenderKitMetadataSidecarPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    return Join-Path `
        -Path $file.DirectoryName `
        -ChildPath ('.{0}.renderkit.metadata.json' -f $file.Name)
}

function Get-RenderKitFileMetadataLocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$ProjectRoot
    )

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $resolvedProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
        if (-not (Test-RenderKitPathInsideRoot -Path $file.FullName -RootPath $resolvedProjectRoot)) {
            throw "File '$($file.FullName)' is outside project root '$resolvedProjectRoot'."
        }

        $relativePath = ConvertTo-RenderKitProjectRelativePath `
            -BasePath $resolvedProjectRoot `
            -Path $file.FullName
        $fileId = ConvertTo-RenderKitSha256Text `
            -Text ($relativePath.ToLowerInvariant())
        $metadataRoot = Join-Path -Path $resolvedProjectRoot -ChildPath '.renderkit/metadata/files'
        $recordPath = Join-Path -Path $metadataRoot -ChildPath ('{0}.json' -f $fileId)
        return [PSCustomObject]@{
            StorageMode = 'ProjectStore'
            RecordPath = [System.IO.Path]::GetFullPath($recordPath)
            FileId = $fileId
            RelativePath = $relativePath
            ProjectRoot = $resolvedProjectRoot
        }
    }

    $sidecarPath = Get-RenderKitMetadataSidecarPath -Path $file.FullName
    $sidecarId = ConvertTo-RenderKitSha256Text `
        -Text ($file.FullName.ToLowerInvariant())
    return [PSCustomObject]@{
        StorageMode = 'Sidecar'
        RecordPath = [System.IO.Path]::GetFullPath($sidecarPath)
        FileId = $sidecarId
        RelativePath = $null
        ProjectRoot = $null
    }
}

function Test-RenderKitFileMetadataRecordSchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Record
    )

    if ([string]$Record.artifactType -ne 'FileMetadataRecord') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Record.schemaVersion)) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Record.fileId)) {
        return $false
    }
    if ($null -eq $Record.metadata) {
        return $false
    }

    $compatibility = Test-RenderKitArtifactCompatibility `
        -ArtifactType FileMetadataRecord `
        -Version ([string]$Record.schemaVersion)
    return [bool]($compatibility.CanRead -and $compatibility.CanWrite)
}

function ConvertTo-RenderKitMetadataDictionary {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [switch]$Persistable
    )

    $skipForPersistence = @(
        'AccessedAtFileSystem'
    )
    $dictionary = [ordered]@{}
    if ($null -eq $Value) {
        return $dictionary
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | Sort-Object)
        foreach ($key in $keys) {
            $name = [string]$key
            if ($Persistable -and $skipForPersistence -contains $name) {
                continue
            }
            $itemValue = $Value[$key]
            if (-not (Test-RenderKitMetadataValueIsEmpty -Value $itemValue)) {
                $dictionary[$name] = $itemValue
            }
        }
        return $dictionary
    }

    foreach ($property in @($Value.PSObject.Properties | Sort-Object -Property Name)) {
        $name = [string]$property.Name
        if ($Persistable -and $skipForPersistence -contains $name) {
            continue
        }
        if (-not (Test-RenderKitMetadataValueIsEmpty -Value $property.Value)) {
            $dictionary[$name] = $property.Value
        }
    }

    return $dictionary
}

function ConvertTo-RenderKitMetadataComparableJson {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Value
    )

    $dictionary = ConvertTo-RenderKitMetadataDictionary -Value $Value
    return ($dictionary | ConvertTo-Json -Depth 30 -Compress)
}

function Read-RenderKitFileMetadataRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$ProjectRoot
    )

    $location = Get-RenderKitFileMetadataLocation `
        -Path $Path `
        -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $location.RecordPath -PathType Leaf)) {
        return $null
    }

    return Read-RenderKitJsonFile `
        -Path $location.RecordPath `
        -MaximumBytes 52428800 `
        -Validator { param($value) Test-RenderKitFileMetadataRecordSchema -Record $value }
}

function New-RenderKitFileMetadataRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MetadataResult,

        [Parameter(Mandatory)]
        [object]$Location,

        [object]$CurrentRecord,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata
    )

    $file = Get-Item -LiteralPath ([string]$MetadataResult.Path) -ErrorAction Stop
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $currentVersion = if ($CurrentRecord -and $CurrentRecord.version) {
        [int]$CurrentRecord.version
    }
    else {
        0
    }
    $currentMetadataJson = if ($CurrentRecord) {
        ConvertTo-RenderKitMetadataComparableJson -Value $CurrentRecord.metadata
    }
    else {
        $null
    }
    $nextMetadataJson = ConvertTo-RenderKitMetadataComparableJson -Value $Metadata
    $metadataChanged = $currentMetadataJson -ne $nextMetadataJson
    $version = if ($CurrentRecord) {
        if ($metadataChanged) { $currentVersion + 1 } else { $currentVersion }
    }
    else {
        1
    }

    $history = @()
    if ($CurrentRecord -and $CurrentRecord.history) {
        $history = @($CurrentRecord.history)
    }
    if ($CurrentRecord -and $metadataChanged) {
        $history += [PSCustomObject]@{
            version = [int]$CurrentRecord.version
            updatedAtUtc = [string]$CurrentRecord.updatedAtUtc
            metadata = $CurrentRecord.metadata
            extraction = $CurrentRecord.extraction
        }
    }

    $createdAtUtc = if ($CurrentRecord -and $CurrentRecord.createdAtUtc) {
        [string]$CurrentRecord.createdAtUtc
    }
    else {
        $now
    }

    return [PSCustomObject]@{
        tool = 'RenderKit'
        schemaVersion = '1.0'
        artifactType = 'FileMetadataRecord'
        fileId = [string]$Location.FileId
        version = $version
        createdAtUtc = $createdAtUtc
        updatedAtUtc = if ($metadataChanged -or -not $CurrentRecord) { $now } else { [string]$CurrentRecord.updatedAtUtc }
        storage = [PSCustomObject]@{
            mode = [string]$Location.StorageMode
            relativePath = if ($Location.RelativePath) { [string]$Location.RelativePath } else { $null }
            projectRootRelative = if ($Location.ProjectRoot) { '.renderkit/metadata/files' } else { $null }
        }
        file = [PSCustomObject]@{
            name = $file.Name
            extension = $file.Extension
            sizeBytes = [int64]$file.Length
            lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
        }
        metadata = [PSCustomObject]$Metadata
        extraction = [PSCustomObject]@{
            extractedAtUtc = $now
            mediaKind = [string]$MetadataResult.MediaKind
            mimeType = [string]$MetadataResult.MimeType
            adapterIds = @($MetadataResult.AdapterIds)
            readers = @($MetadataResult.Readers)
            warnings = @($MetadataResult.Warnings)
        }
        history = @($history)
    }
}

function Write-RenderKitFileMetadataRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$MetadataResult,

        [string]$ProjectRoot
    )

    $location = Get-RenderKitFileMetadataLocation `
        -Path ([string]$MetadataResult.Path) `
        -ProjectRoot $ProjectRoot
    $current = $null
    if (Test-Path -LiteralPath $location.RecordPath -PathType Leaf) {
        $current = Read-RenderKitJsonFile `
            -Path $location.RecordPath `
            -MaximumBytes 52428800 `
            -Validator { param($value) Test-RenderKitFileMetadataRecordSchema -Record $value }
    }

    $metadata = ConvertTo-RenderKitMetadataDictionary `
        -Value $MetadataResult.Fields `
        -Persistable
    $record = New-RenderKitFileMetadataRecord `
        -MetadataResult $MetadataResult `
        -Location $location `
        -CurrentRecord $current `
        -Metadata $metadata

    $currentJson = if ($current) {
        ConvertTo-RenderKitMetadataComparableJson -Value $current.metadata
    }
    else {
        $null
    }
    $nextJson = ConvertTo-RenderKitMetadataComparableJson -Value $metadata
    $shouldWrite = -not $current -or $currentJson -ne $nextJson

    if ($shouldWrite) {
        Write-RenderKitJsonFileAtomic `
            -Path $location.RecordPath `
            -Value $record `
            -Depth 40 `
            -Validator { param($value) Test-RenderKitFileMetadataRecordSchema -Record $value } |
            Out-Null
    }

    return [PSCustomObject]@{
        Record = $record
        RecordPath = [string]$location.RecordPath
        StorageMode = [string]$location.StorageMode
        Version = [int]$record.version
        Written = [bool]$shouldWrite
    }
}

function New-RenderKitMetadataMutationReadResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [AllowNull()]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata,

        [string[]]$Warning
    )

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $route = Resolve-RenderKitMetadataAdapterRoute -Path $file.FullName
    return [PSCustomObject]@{
        Path = $file.FullName
        ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $null } else { [System.IO.Path]::GetFullPath($ProjectRoot) }
        FileName = $file.Name
        MediaKind = [string]$route.MediaKind
        Extension = [string]$route.Extension
        MimeType = [string]$route.MimeType
        IsSupported = [bool]$route.IsSupported
        AdapterIds = @($route.AdapterIds)
        Readers = @($route.Readers)
        Fields = [PSCustomObject]$Metadata
        Warnings = @($Warning)
        Raw = $null
    }
}

function Set-RenderKitFileMetadataRecordField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Metadata,

        [string]$ProjectRoot,

        [switch]$Override
    )

    $location = Get-RenderKitFileMetadataLocation `
        -Path $Path `
        -ProjectRoot $ProjectRoot
    $current = $null
    if (Test-Path -LiteralPath $location.RecordPath -PathType Leaf) {
        $current = Read-RenderKitJsonFile `
            -Path $location.RecordPath `
            -MaximumBytes 52428800 `
            -Validator { param($value) Test-RenderKitFileMetadataRecordSchema -Record $value }
    }

    $nextMetadata = [ordered]@{}
    if ($current -and $current.metadata) {
        $nextMetadata = ConvertTo-RenderKitMetadataDictionary -Value $current.metadata
    }

    $changes = New-Object System.Collections.Generic.List[object]
    $skipped = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($Metadata.Keys | Sort-Object)) {
        $fieldName = [string]$key
        $value = $Metadata[$key]
        if (Test-RenderKitMetadataValueIsEmpty -Value $value) {
            $skipped.Add([PSCustomObject]@{
                Field = $fieldName
                Reason = 'EmptyValue'
                ExistingValue = $null
            })
            continue
        }

        $hasExistingValue = $nextMetadata.Contains($fieldName) -and
            -not (Test-RenderKitMetadataValueIsEmpty -Value $nextMetadata[$fieldName])
        if ($hasExistingValue -and -not $Override) {
            $skipped.Add([PSCustomObject]@{
                Field = $fieldName
                Reason = 'ExistingValue'
                ExistingValue = $nextMetadata[$fieldName]
            })
            continue
        }

        $oldValue = if ($nextMetadata.Contains($fieldName)) { $nextMetadata[$fieldName] } else { $null }
        Set-RenderKitMetadataFieldValue `
            -Fields $nextMetadata `
            -Name $fieldName `
            -Value $value
        if ($oldValue -ne $nextMetadata[$fieldName]) {
            $changes.Add([PSCustomObject]@{
                Field = $fieldName
                OldValue = $oldValue
                NewValue = $nextMetadata[$fieldName]
            })
        }
    }

    if ($changes.Count -eq 0) {
        return [PSCustomObject]@{
            Record = $current
            RecordPath = [string]$location.RecordPath
            StorageMode = [string]$location.StorageMode
            Version = if ($current) { [int]$current.version } else { 0 }
            Written = $false
            Changes = @()
            Skipped = @($skipped.ToArray())
        }
    }

    $readResult = New-RenderKitMetadataMutationReadResult `
        -Path $Path `
        -ProjectRoot $ProjectRoot `
        -Metadata $nextMetadata
    $store = Write-RenderKitFileMetadataRecord `
        -MetadataResult $readResult `
        -ProjectRoot $ProjectRoot

    return [PSCustomObject]@{
        Record = $store.Record
        RecordPath = [string]$store.RecordPath
        StorageMode = [string]$store.StorageMode
        Version = [int]$store.Version
        Written = [bool]$store.Written
        Changes = @($changes.ToArray())
        Skipped = @($skipped.ToArray())
    }
}

function Restore-RenderKitFileMetadataRecordVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$ProjectRoot,

        [int]$Version
    )

    $location = Get-RenderKitFileMetadataLocation `
        -Path $Path `
        -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $location.RecordPath -PathType Leaf)) {
        throw "Metadata record was not found for '$Path'."
    }

    $current = Read-RenderKitJsonFile `
        -Path $location.RecordPath `
        -MaximumBytes 52428800 `
        -Validator { param($value) Test-RenderKitFileMetadataRecordSchema -Record $value }

    $history = @($current.history)
    if ($history.Count -eq 0) {
        throw "Metadata record for '$Path' has no rollback history."
    }

    $target = if ($Version -gt 0) {
        @($history | Where-Object { [int]$_.version -eq $Version } | Select-Object -First 1)
    }
    else {
        @($history | Select-Object -Last 1)
    }
    if (-not $target) {
        throw "Metadata version '$Version' was not found in rollback history."
    }

    if ([int]$target.version -eq [int]$current.version) {
        return [PSCustomObject]@{
            Record = $current
            RecordPath = [string]$location.RecordPath
            StorageMode = [string]$location.StorageMode
            Version = [int]$current.version
            RolledBack = $false
            RestoredFromVersion = [int]$target.version
        }
    }

    $metadata = ConvertTo-RenderKitMetadataDictionary -Value $target.metadata
    $readResult = New-RenderKitMetadataMutationReadResult `
        -Path $Path `
        -ProjectRoot $ProjectRoot `
        -Metadata $metadata `
        -Warning @("Rolled back from version $($current.version) to version $($target.version).")
    $store = Write-RenderKitFileMetadataRecord `
        -MetadataResult $readResult `
        -ProjectRoot $ProjectRoot

    return [PSCustomObject]@{
        Record = $store.Record
        RecordPath = [string]$store.RecordPath
        StorageMode = [string]$store.StorageMode
        Version = [int]$store.Version
        RolledBack = [bool]$store.Written
        RestoredFromVersion = [int]$target.version
    }
}

function Get-RenderKitProjectMetadataBatchRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $resolvedProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    return New-RenderKitStorageDirectory `
        -Path (Join-Path -Path $resolvedProjectRoot -ChildPath '.renderkit/metadata/batches')
}

function Get-RenderKitProjectMetadataBatchPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$BatchId
    )

    if ($BatchId -notmatch '^[0-9a-fA-F-]{36}$') {
        throw "Metadata batch id '$BatchId' is not valid."
    }

    return Join-Path `
        -Path (Get-RenderKitProjectMetadataBatchRoot -ProjectRoot $ProjectRoot) `
        -ChildPath "$BatchId.json"
}

function Test-RenderKitMetadataBatchRecordSchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Batch
    )

    if ([string]$Batch.artifactType -ne 'MetadataBatch') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Batch.schemaVersion)) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Batch.batchId)) {
        return $false
    }
    if ($null -eq $Batch.entries) {
        return $false
    }

    $compatibility = Test-RenderKitArtifactCompatibility `
        -ArtifactType MetadataBatch `
        -Version ([string]$Batch.schemaVersion)
    return [bool]($compatibility.CanRead -and $compatibility.CanWrite)
}

function Write-RenderKitMetadataBatchRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [object]$Batch
    )

    $path = Get-RenderKitProjectMetadataBatchPath `
        -ProjectRoot $ProjectRoot `
        -BatchId ([string]$Batch.batchId)
    Write-RenderKitJsonFileAtomic `
        -Path $path `
        -Value $Batch `
        -Depth 40 `
        -Validator { param($value) Test-RenderKitMetadataBatchRecordSchema -Batch $value } |
        Out-Null
    return [PSCustomObject]@{
        Batch = $Batch
        Path = $path
    }
}

function Read-RenderKitMetadataBatchRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$BatchId
    )

    $path = Get-RenderKitProjectMetadataBatchPath `
        -ProjectRoot $ProjectRoot `
        -BatchId $BatchId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Metadata batch '$BatchId' was not found in project '$ProjectRoot'."
    }

    $batch = Read-RenderKitJsonFile `
        -Path $path `
        -MaximumBytes 52428800 `
        -Validator { param($value) Test-RenderKitMetadataBatchRecordSchema -Batch $value }
    return [PSCustomObject]@{
        Batch = $batch
        Path = $path
    }
}

function New-RenderKitMetadataBatchRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$TemplateName,

        [Parameter(Mandatory)]
        [int]$TemplateGeneration,

        [Parameter(Mandatory)]
        [string]$StartedAtUtc,

        [Parameter(Mandatory)]
        [object[]]$Entries,

        [switch]$Override
    )

    $endedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $successCount = @($Entries | Where-Object { [string]$_.status -eq 'Succeeded' }).Count
    $failedCount = @($Entries | Where-Object { [string]$_.status -eq 'Failed' }).Count
    $skippedCount = @($Entries | Where-Object { [string]$_.status -eq 'Skipped' }).Count

    return [PSCustomObject]@{
        tool = 'RenderKit'
        schemaVersion = '1.0'
        artifactType = 'MetadataBatch'
        batchId = ([guid]::NewGuid()).Guid
        operation = 'ApplyMetadataTemplate'
        projectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
        template = [PSCustomObject]@{
            name = $TemplateName
            generation = $TemplateGeneration
        }
        options = [PSCustomObject]@{
            override = [bool]$Override
        }
        startedAtUtc = $StartedAtUtc
        endedAtUtc = $endedAtUtc
        summary = [PSCustomObject]@{
            total = @($Entries).Count
            succeeded = $successCount
            failed = $failedCount
            skipped = $skippedCount
        }
        entries = @($Entries)
    }
}

function Invoke-RenderKitMetadataBatchRollback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$BatchId
    )

    $context = Read-RenderKitMetadataBatchRecord `
        -ProjectRoot $ProjectRoot `
        -BatchId $BatchId
    $batch = $context.Batch
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($entry in @($batch.entries)) {
        if ([string]$entry.status -ne 'Succeeded') {
            $results.Add([PSCustomObject]@{
                Path = [string]$entry.path
                RelativePath = [string]$entry.relativePath
                Status = 'Skipped'
                Reason = 'EntryDidNotSucceed'
                Version = $null
            })
            continue
        }

        try {
            $path = [string]$entry.path
            if ([string]::IsNullOrWhiteSpace($path) -and -not [string]::IsNullOrWhiteSpace([string]$entry.relativePath)) {
                $path = Join-Path -Path $ProjectRoot -ChildPath ([string]$entry.relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            }
            $beforeVersion = [int]$entry.beforeVersion
            if ($beforeVersion -gt 0) {
                $rollback = Restore-RenderKitFileMetadataRecordVersion `
                    -Path $path `
                    -ProjectRoot $ProjectRoot `
                    -Version $beforeVersion
                $results.Add([PSCustomObject]@{
                    Path = $path
                    RelativePath = [string]$entry.relativePath
                    Status = 'RolledBack'
                    Reason = $null
                    Version = [int]$rollback.Version
                })
            }
            else {
                $location = Get-RenderKitFileMetadataLocation `
                    -Path $path `
                    -ProjectRoot $ProjectRoot
                if (Test-Path -LiteralPath $location.RecordPath -PathType Leaf) {
                    Remove-Item -LiteralPath $location.RecordPath -Force
                }
                $results.Add([PSCustomObject]@{
                    Path = $path
                    RelativePath = [string]$entry.relativePath
                    Status = 'Removed'
                    Reason = $null
                    Version = 0
                })
            }
        }
        catch {
            $results.Add([PSCustomObject]@{
                Path = [string]$entry.path
                RelativePath = [string]$entry.relativePath
                Status = 'Failed'
                Reason = $_.Exception.Message
                Version = $null
            })
        }
    }

    return [PSCustomObject]@{
        BatchId = $BatchId
        ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
        BatchPath = [string]$context.Path
        Total = $results.Count
        RolledBack = @($results | Where-Object { $_.Status -in @('RolledBack', 'Removed') }).Count
        Succeeded = @($results | Where-Object { $_.Status -in @('RolledBack', 'Removed') }).Count
        Failed = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
        Skipped = @($results | Where-Object { $_.Status -eq 'Skipped' }).Count
        Entries = @($results.ToArray())
    }
}
