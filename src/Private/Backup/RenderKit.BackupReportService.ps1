function Get-BackupReportObjectValue {
    [CmdletBinding()]
    param(
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        return $DefaultValue
    }
    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }

    return $DefaultValue
}

function ConvertTo-BackupReportArray {
    [CmdletBinding()]
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return @()
    }

    return @($Value)
}

function ConvertTo-BackupReportFormatList {
    [CmdletBinding()]
    param(
        [string[]]$Format
    )

    $requested = if ($Format -and @($Format).Count -gt 0) { @($Format) } else { @('Json', 'Html', 'Text') }
    $formats = New-Object System.Collections.Generic.List[string]
    foreach ($item in $requested) {
        if ([string]::IsNullOrWhiteSpace([string]$item)) {
            continue
        }

        $normalized = switch (([string]$item).Trim().ToLowerInvariant()) {
            'json' { 'Json'; break }
            'html' { 'Html'; break }
            'htm' { 'Html'; break }
            'text' { 'Text'; break }
            'txt' { 'Text'; break }
            default {
                throw "Backup report format '$item' is not supported. Use Json, Html, or Text."
            }
        }

        if (-not $formats.Contains($normalized)) {
            $formats.Add($normalized)
        }
    }

    if ($formats.Count -eq 0) {
        $formats.Add('Json')
        $formats.Add('Html')
        $formats.Add('Text')
    }

    return @($formats.ToArray())
}

function ConvertTo-BackupReportHumanSize {
    [CmdletBinding()]
    param(
        [object]$Bytes
    )

    if ($null -eq $Bytes) {
        return '-'
    }

    try {
        return ConvertTo-RenderKitHumanSize -Bytes ([int64]$Bytes)
    }
    catch {
        return ("{0} bytes" -f [int64]$Bytes)
    }
}

function ConvertTo-BackupReportDurationText {
    [CmdletBinding()]
    param(
        [object]$Seconds
    )

    if ($null -eq $Seconds) {
        return '-'
    }

    $duration = [TimeSpan]::FromSeconds([double]$Seconds)
    if ($duration.TotalHours -ge 1) {
        return ('{0:00}:{1:00}:{2:00}' -f [int]$duration.TotalHours, $duration.Minutes, $duration.Seconds)
    }

    return ('{0:00}:{1:00}' -f [int]$duration.TotalMinutes, $duration.Seconds)
}

function New-BackupReportPlan {
    [CmdletBinding()]
    param(
        [string]$ArchivePath,
        [string]$ReportRoot,
        [string[]]$Format = @('Json', 'Html', 'Text')
    )

    $formats = ConvertTo-BackupReportFormatList -Format $Format
    $destinationRoot = $ReportRoot
    if ([string]::IsNullOrWhiteSpace($destinationRoot) -and
        -not [string]::IsNullOrWhiteSpace($ArchivePath) -and
        -not (Test-BackupPathLooksLikeUri -Path $ArchivePath)) {
        $destinationRoot = Split-Path -Path $ArchivePath -Parent
    }

    $baseName = if (-not [string]::IsNullOrWhiteSpace($ArchivePath) -and -not (Test-BackupPathLooksLikeUri -Path $ArchivePath)) {
        [System.IO.Path]::GetFileNameWithoutExtension($ArchivePath)
    }
    else {
        'backup'
    }

    $files = New-Object System.Collections.Generic.List[object]
    $paths = [ordered]@{
        json = $null
        html = $null
        text = $null
    }

    foreach ($format in $formats) {
        $extension = switch ($format) {
            'Json' { 'json' }
            'Html' { 'html' }
            'Text' { 'txt' }
        }
        $fileName = '{0}.report.{1}' -f $baseName, $extension
        $path = if ([string]::IsNullOrWhiteSpace($destinationRoot)) {
            $null
        }
        else {
            Join-Path -Path $destinationRoot -ChildPath $fileName
        }

        $paths[$extension -replace '^txt$', 'text'] = $path
        $files.Add([PSCustomObject]@{
                format      = $format
                fileName    = $fileName
                path        = $path
                contentType = switch ($format) {
                    'Json' { 'application/json' }
                    'Html' { 'text/html' }
                    'Text' { 'text/plain' }
                }
            })
    }

    return [PSCustomObject]@{
        schemaVersion   = '1.0'
        enabled         = $true
        state           = 'Planned'
        mode            = 'SidecarAuditReports'
        formats         = @($formats)
        destinationRoot = $destinationRoot
        files           = @($files.ToArray())
        paths           = [PSCustomObject]$paths
    }
}

function New-BackupAuditReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Project,
        [Parameter(Mandatory)]
        [object]$Archive,
        [hashtable]$Statistics,
        [object]$Manifest,
        [object[]]$StorageTiers,
        [hashtable]$SourceIndex,
        [array]$CleanupSummary,
        [object]$ReportPlan
    )

    if (-not $Statistics) {
        $Statistics = @{}
    }
    if (-not $CleanupSummary) {
        $CleanupSummary = @()
    }

    $sourceChecksums = New-Object System.Collections.Generic.List[object]
    if ($SourceIndex) {
        foreach ($entry in @($SourceIndex.Values | Sort-Object RelativePath)) {
            $sourceChecksums.Add([PSCustomObject]@{
                    relativePath  = [string]$entry.RelativePath
                    lengthBytes   = [int64]$entry.Length
                    lengthText    = ConvertTo-BackupReportHumanSize -Bytes ([int64]$entry.Length)
                    hashAlgorithm = [string]$entry.Algorithm
                    hash          = [string]$entry.Hash
                })
        }
    }

    $storageVerification = Get-BackupReportObjectValue -InputObject $Archive -Name 'storageVerification'
    $storageTierResults = ConvertTo-BackupReportArray -Value (Get-BackupReportObjectValue -InputObject $storageVerification -Name 'tiers')
    $targets = New-Object System.Collections.Generic.List[object]
    foreach ($tier in $storageTierResults) {
        $targets.Add([PSCustomObject]@{
                tierId        = [string](Get-BackupReportObjectValue -InputObject $tier -Name 'tierId')
                tierName      = [string](Get-BackupReportObjectValue -InputObject $tier -Name 'tierName')
                profile       = [string](Get-BackupReportObjectValue -InputObject $tier -Name 'profile')
                required      = [bool](Get-BackupReportObjectValue -InputObject $tier -Name 'required' -DefaultValue $false)
                targetPath    = [string](Get-BackupReportObjectValue -InputObject $tier -Name 'targetPath')
                state         = [string](Get-BackupReportObjectValue -InputObject $tier -Name 'state')
                verified      = [bool](Get-BackupReportObjectValue -InputObject $tier -Name 'verified' -DefaultValue $false)
                copied        = [bool](Get-BackupReportObjectValue -InputObject $tier -Name 'copied' -DefaultValue $false)
                sizeBytes     = Get-BackupReportObjectValue -InputObject $tier -Name 'sizeBytes'
                sourceHash    = [string](Get-BackupReportObjectValue -InputObject $tier -Name 'sourceHash')
                targetHash    = [string](Get-BackupReportObjectValue -InputObject $tier -Name 'targetHash')
                completedAtUtc = [string](Get-BackupReportObjectValue -InputObject $tier -Name 'completedAtUtc')
                error         = [string](Get-BackupReportObjectValue -InputObject $tier -Name 'error')
                health        = Get-BackupReportObjectValue -InputObject $tier -Name 'health'
            })
    }

    $archiveHashAlgorithm = [string](Get-BackupReportObjectValue -InputObject $Archive -Name 'hashAlgorithm')
    $archiveHash = [string](Get-BackupReportObjectValue -InputObject $Archive -Name 'hash')
    $archiveSizeBytes = Get-BackupReportObjectValue -InputObject $Archive -Name 'sizeBytes' -DefaultValue 0
    $sourceStats = Get-BackupReportObjectValue -InputObject $Statistics -Name 'source' -DefaultValue @{}
    $beforeStats = Get-BackupReportObjectValue -InputObject $Statistics -Name 'before' -DefaultValue @{}
    $afterStats = Get-BackupReportObjectValue -InputObject $Statistics -Name 'after' -DefaultValue @{}
    $cleanupStats = Get-BackupReportObjectValue -InputObject $Statistics -Name 'cleanup' -DefaultValue @{}
    $artifactRemoved = Get-BackupReportObjectValue -InputObject $cleanupStats -Name 'artifactRemoved' -DefaultValue @{}
    $dedupStats = Get-BackupReportObjectValue -InputObject $Statistics -Name 'deduplication' -DefaultValue @{}
    $contentIntegrity = Get-BackupReportObjectValue -InputObject $Archive -Name 'contentIntegrity'
    $safeDelete = Get-BackupReportObjectValue -InputObject $Archive -Name 'safeDelete'

    $errors = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($CleanupSummary)) {
        if ([int](Get-BackupReportObjectValue -InputObject $row -Name 'FailedCount' -DefaultValue 0) -gt 0) {
            $errors.Add([PSCustomObject]@{
                    scope   = 'Cleanup'
                    code    = 'CleanupFailed'
                    message = ("{0} reported {1} failed item(s)." -f [string]$row.Step, [int]$row.FailedCount)
                    details = $row
                })
        }
    }
    if ($contentIntegrity -and [bool](Get-BackupReportObjectValue -InputObject $contentIntegrity -Name 'checked' -DefaultValue $false) -and
        -not [bool](Get-BackupReportObjectValue -InputObject $contentIntegrity -Name 'isMatch' -DefaultValue $false)) {
        $errors.Add([PSCustomObject]@{
                scope   = 'ArchiveIntegrity'
                code    = 'ArchiveIntegrityMismatch'
                message = 'Archive content integrity did not match the source index.'
                details = $contentIntegrity
            })
    }
    foreach ($target in @($targets.ToArray())) {
        if (-not [bool]$target.verified -and -not [string]::IsNullOrWhiteSpace([string]$target.error)) {
            $errors.Add([PSCustomObject]@{
                    scope   = 'StorageTier'
                    code    = [string]$target.state
                    message = [string]$target.error
                    details = $target
                })
        }
    }
    foreach ($failedRule in @(Get-BackupReportObjectValue -InputObject $safeDelete -Name 'failedRules' -DefaultValue @())) {
        $errors.Add([PSCustomObject]@{
                scope   = 'SafeDelete'
                code    = [string](Get-BackupReportObjectValue -InputObject $failedRule -Name 'rule')
                message = [string](Get-BackupReportObjectValue -InputObject $failedRule -Name 'reason')
                details = $failedRule
            })
    }

    $cleanupSavedBytes = [int64](Get-BackupReportObjectValue -InputObject $artifactRemoved -Name 'bytes' -DefaultValue 0)
    $dedupSavedBytes = [int64](Get-BackupReportObjectValue -InputObject $dedupStats -Name 'estimatedSavedBytes' -DefaultValue 0)
    $sourceBeforeBytes = [int64](Get-BackupReportObjectValue -InputObject $beforeStats -Name 'totalBytes' -DefaultValue 0)
    $sourceAfterBytes = [int64](Get-BackupReportObjectValue -InputObject $afterStats -Name 'totalBytes' -DefaultValue 0)

    return [PSCustomObject]@{
        schemaVersion  = '1.0'
        kind           = 'BackupAuditReport'
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        backup         = [PSCustomObject]@{
            id        = if ($Manifest -and $Manifest.backup) { [string]$Manifest.backup.id } else { $null }
            createdAt = if ($Manifest -and $Manifest.backup) { [string]$Manifest.backup.createdAt } else { $null }
            tool      = if ($Manifest -and $Manifest.backup) { $Manifest.backup.tool } else { $null }
        }
        project        = [PSCustomObject]@{
            id       = [string](Get-BackupReportObjectValue -InputObject $Project -Name 'Id')
            name     = [string](Get-BackupReportObjectValue -InputObject $Project -Name 'Name')
            rootPath = [string](Get-BackupReportObjectValue -InputObject $Project -Name 'RootPath')
        }
        duration       = [PSCustomObject]@{
            startedAtUtc    = [string](Get-BackupReportObjectValue -InputObject $Statistics -Name 'startedAt')
            endedAtUtc      = [string](Get-BackupReportObjectValue -InputObject $Statistics -Name 'endedAt')
            durationSeconds = [double](Get-BackupReportObjectValue -InputObject $Statistics -Name 'durationSeconds' -DefaultValue 0)
            durationText    = ConvertTo-BackupReportDurationText -Seconds (Get-BackupReportObjectValue -InputObject $Statistics -Name 'durationSeconds' -DefaultValue 0)
        }
        source         = [PSCustomObject]@{
            path             = [string](Get-BackupReportObjectValue -InputObject $sourceStats -Name 'path')
            removed          = [bool](Get-BackupReportObjectValue -InputObject $sourceStats -Name 'removed' -DefaultValue $false)
            removalScheduled = [bool](Get-BackupReportObjectValue -InputObject $sourceStats -Name 'removalScheduled' -DefaultValue $false)
            existsAfterRun   = [bool](Get-BackupReportObjectValue -InputObject $sourceStats -Name 'existsAfterRun' -DefaultValue $false)
            fileCountBefore  = [int](Get-BackupReportObjectValue -InputObject $beforeStats -Name 'fileCount' -DefaultValue 0)
            fileCountAfterCleanup = [int](Get-BackupReportObjectValue -InputObject $afterStats -Name 'fileCount' -DefaultValue 0)
            totalBytesBefore = $sourceBeforeBytes
            totalBytesBeforeText = ConvertTo-BackupReportHumanSize -Bytes $sourceBeforeBytes
            totalBytesAfterCleanup = $sourceAfterBytes
            totalBytesAfterCleanupText = ConvertTo-BackupReportHumanSize -Bytes $sourceAfterBytes
            checksums        = @($sourceChecksums.ToArray())
        }
        archive        = [PSCustomObject]@{
            path          = [string](Get-BackupReportObjectValue -InputObject $Archive -Name 'path')
            fileName      = [string](Get-BackupReportObjectValue -InputObject $Archive -Name 'fileName')
            exists        = [bool](Get-BackupReportObjectValue -InputObject $Archive -Name 'exists' -DefaultValue $false)
            sizeBytes     = [int64]$archiveSizeBytes
            sizeText      = ConvertTo-BackupReportHumanSize -Bytes $archiveSizeBytes
            hashAlgorithm = $archiveHashAlgorithm
            hash          = $archiveHash
            manifest      = Get-BackupReportObjectValue -InputObject $Archive -Name 'manifest'
            contentIntegrity = $contentIntegrity
            logInjection  = Get-BackupReportObjectValue -InputObject $Archive -Name 'logInjection'
        }
        targets        = [PSCustomObject]@{
            state   = [string](Get-BackupReportObjectValue -InputObject $storageVerification -Name 'state')
            release = Get-BackupReportObjectValue -InputObject $storageVerification -Name 'release'
            summary = Get-BackupReportObjectValue -InputObject $storageVerification -Name 'summary'
            tiers   = @($targets.ToArray())
        }
        checksums      = [PSCustomObject]@{
            archive     = [PSCustomObject]@{
                path      = [string](Get-BackupReportObjectValue -InputObject $Archive -Name 'path')
                algorithm = $archiveHashAlgorithm
                hash      = $archiveHash
            }
            sourceFiles = @($sourceChecksums.ToArray())
            targets     = @($targets.ToArray() | ForEach-Object {
                    [PSCustomObject]@{
                        tierId     = $_.tierId
                        targetPath = $_.targetPath
                        algorithm  = $archiveHashAlgorithm
                        sourceHash = $_.sourceHash
                        targetHash = $_.targetHash
                        verified   = $_.verified
                    }
                })
        }
        savings        = [PSCustomObject]@{
            cleanupRemovedBytes       = $cleanupSavedBytes
            cleanupRemovedText        = ConvertTo-BackupReportHumanSize -Bytes $cleanupSavedBytes
            deduplicatedBytes         = $dedupSavedBytes
            deduplicatedText          = ConvertTo-BackupReportHumanSize -Bytes $dedupSavedBytes
            estimatedTotalSavedBytes  = [int64]($cleanupSavedBytes + $dedupSavedBytes)
            estimatedTotalSavedText   = ConvertTo-BackupReportHumanSize -Bytes ([int64]($cleanupSavedBytes + $dedupSavedBytes))
            sourceBeforeBytes         = $sourceBeforeBytes
            sourceAfterCleanupBytes   = $sourceAfterBytes
            archiveBytes              = [int64]$archiveSizeBytes
        }
        deduplication  = Get-BackupReportObjectValue -InputObject $Archive -Name 'deduplication'
        cleanup        = @($CleanupSummary)
        errors         = @($errors.ToArray())
        reports        = $ReportPlan
    }
}

function ConvertTo-BackupAuditReportText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Report
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('RenderKit Backup Audit Report')
    $lines.Add(('GeneratedAtUtc: {0}' -f [string]$Report.generatedAtUtc))
    $lines.Add(('BackupId: {0}' -f [string]$Report.backup.id))
    $lines.Add('')
    $lines.Add('[Project]')
    $lines.Add(('Name: {0}' -f [string]$Report.project.name))
    $lines.Add(('Id: {0}' -f [string]$Report.project.id))
    $lines.Add(('RootPath: {0}' -f [string]$Report.project.rootPath))
    $lines.Add('')
    $lines.Add('[Duration]')
    $lines.Add(('StartedAtUtc: {0}' -f [string]$Report.duration.startedAtUtc))
    $lines.Add(('EndedAtUtc: {0}' -f [string]$Report.duration.endedAtUtc))
    $lines.Add(('DurationSeconds: {0:N3}' -f [double]$Report.duration.durationSeconds))
    $lines.Add(('Duration: {0}' -f [string]$Report.duration.durationText))
    $lines.Add('')
    $lines.Add('[Source]')
    $lines.Add(('Path: {0}' -f [string]$Report.source.path))
    $lines.Add(('Removed: {0}' -f [bool]$Report.source.removed))
    $lines.Add(('ExistsAfterRun: {0}' -f [bool]$Report.source.existsAfterRun))
    $lines.Add(('FilesBefore: {0}' -f [int]$Report.source.fileCountBefore))
    $lines.Add(('FilesAfterCleanup: {0}' -f [int]$Report.source.fileCountAfterCleanup))
    $lines.Add(('BytesBefore: {0} ({1})' -f [int64]$Report.source.totalBytesBefore, [string]$Report.source.totalBytesBeforeText))
    $lines.Add('')
    $lines.Add('[Archive]')
    $lines.Add(('Path: {0}' -f [string]$Report.archive.path))
    $lines.Add(('Size: {0} ({1})' -f [int64]$Report.archive.sizeBytes, [string]$Report.archive.sizeText))
    $lines.Add(('HashAlgorithm: {0}' -f [string]$Report.archive.hashAlgorithm))
    $lines.Add(('Hash: {0}' -f [string]$Report.archive.hash))
    $lines.Add(('IntegrityMatch: {0}' -f [string]$Report.archive.contentIntegrity.isMatch))
    $lines.Add('')
    $lines.Add('[Savings]')
    $lines.Add(('CleanupRemoved: {0} ({1})' -f [int64]$Report.savings.cleanupRemovedBytes, [string]$Report.savings.cleanupRemovedText))
    $lines.Add(('Deduplicated: {0} ({1})' -f [int64]$Report.savings.deduplicatedBytes, [string]$Report.savings.deduplicatedText))
    $lines.Add(('EstimatedTotalSaved: {0} ({1})' -f [int64]$Report.savings.estimatedTotalSavedBytes, [string]$Report.savings.estimatedTotalSavedText))
    $lines.Add('')
    $lines.Add('[Targets]')
    foreach ($target in @($Report.targets.tiers)) {
        $lines.Add(('{0}: {1} Verified={2} Hash={3} Error={4}' -f [string]$target.tierName, [string]$target.targetPath, [bool]$target.verified, [string]$target.targetHash, [string]$target.error))
    }
    $lines.Add('')
    $lines.Add('[SourceChecksums]')
    foreach ($file in @($Report.source.checksums)) {
        $lines.Add(('{0} {1} {2} bytes {3}' -f [string]$file.hashAlgorithm, [string]$file.hash, [int64]$file.lengthBytes, [string]$file.relativePath))
    }
    $lines.Add('')
    $lines.Add('[Errors]')
    if (@($Report.errors).Count -eq 0) {
        $lines.Add('None')
    }
    else {
        foreach ($errorItem in @($Report.errors)) {
            $lines.Add(('{0} {1}: {2}' -f [string]$errorItem.scope, [string]$errorItem.code, [string]$errorItem.message))
        }
    }

    return ($lines.ToArray() -join [Environment]::NewLine)
}

function ConvertTo-BackupReportHtmlEncoded {
    [CmdletBinding()]
    param(
        [object]$Value
    )

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-BackupAuditReportHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Report
    )

    $rows = New-Object System.Collections.Generic.List[string]
    $rows.Add('<!doctype html>')
    $rows.Add('<html lang="en">')
    $rows.Add('<head>')
    $rows.Add('<meta charset="utf-8">')
    $rows.Add('<title>RenderKit Backup Audit Report</title>')
    $rows.Add('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:32px;color:#202124;background:#fff}h1{font-size:24px;margin:0 0 4px}h2{font-size:16px;margin:24px 0 8px;border-bottom:1px solid #ddd;padding-bottom:4px}table{border-collapse:collapse;width:100%;margin:8px 0 16px}th,td{text-align:left;border:1px solid #ddd;padding:6px 8px;font-size:13px;vertical-align:top}th{background:#f5f5f5}.muted{color:#666}.ok{color:#137333}.bad{color:#b3261e}code{font-family:Consolas,monospace;font-size:12px}</style>')
    $rows.Add('</head>')
    $rows.Add('<body>')
    $rows.Add('<h1>RenderKit Backup Audit Report</h1>')
    $rows.Add(('<div class="muted">Generated: {0}</div>' -f (ConvertTo-BackupReportHtmlEncoded $Report.generatedAtUtc)))
    $rows.Add('<h2>Summary</h2>')
    $rows.Add('<table><tbody>')
    $rows.Add(('<tr><th>Project</th><td>{0}</td></tr>' -f (ConvertTo-BackupReportHtmlEncoded $Report.project.name)))
    $rows.Add(('<tr><th>Source</th><td><code>{0}</code></td></tr>' -f (ConvertTo-BackupReportHtmlEncoded $Report.source.path)))
    $rows.Add(('<tr><th>Archive</th><td><code>{0}</code></td></tr>' -f (ConvertTo-BackupReportHtmlEncoded $Report.archive.path)))
    $rows.Add(('<tr><th>Duration</th><td>{0} ({1:N3} seconds)</td></tr>' -f (ConvertTo-BackupReportHtmlEncoded $Report.duration.durationText), [double]$Report.duration.durationSeconds))
    $rows.Add(('<tr><th>Estimated saved</th><td>{0}</td></tr>' -f (ConvertTo-BackupReportHtmlEncoded $Report.savings.estimatedTotalSavedText)))
    $rows.Add(('<tr><th>Errors</th><td class="{0}">{1}</td></tr>' -f $(if (@($Report.errors).Count -eq 0) { 'ok' } else { 'bad' }), @($Report.errors).Count))
    $rows.Add('</tbody></table>')
    $rows.Add('<h2>Archive Checksums</h2>')
    $rows.Add('<table><thead><tr><th>Path</th><th>Size</th><th>Algorithm</th><th>Hash</th></tr></thead><tbody>')
    $rows.Add(('<tr><td><code>{0}</code></td><td>{1}</td><td>{2}</td><td><code>{3}</code></td></tr>' -f (ConvertTo-BackupReportHtmlEncoded $Report.archive.path), (ConvertTo-BackupReportHtmlEncoded $Report.archive.sizeText), (ConvertTo-BackupReportHtmlEncoded $Report.archive.hashAlgorithm), (ConvertTo-BackupReportHtmlEncoded $Report.archive.hash)))
    $rows.Add('</tbody></table>')
    $rows.Add('<h2>Targets</h2>')
    $rows.Add('<table><thead><tr><th>Tier</th><th>Target</th><th>State</th><th>Verified</th><th>Target hash</th><th>Error</th></tr></thead><tbody>')
    foreach ($target in @($Report.targets.tiers)) {
        $rows.Add(('<tr><td>{0}</td><td><code>{1}</code></td><td>{2}</td><td>{3}</td><td><code>{4}</code></td><td>{5}</td></tr>' -f (ConvertTo-BackupReportHtmlEncoded $target.tierName), (ConvertTo-BackupReportHtmlEncoded $target.targetPath), (ConvertTo-BackupReportHtmlEncoded $target.state), (ConvertTo-BackupReportHtmlEncoded $target.verified), (ConvertTo-BackupReportHtmlEncoded $target.targetHash), (ConvertTo-BackupReportHtmlEncoded $target.error)))
    }
    $rows.Add('</tbody></table>')
    $rows.Add('<h2>Source Checksums</h2>')
    $rows.Add('<table><thead><tr><th>Relative path</th><th>Size</th><th>Algorithm</th><th>Hash</th></tr></thead><tbody>')
    foreach ($file in @($Report.source.checksums)) {
        $rows.Add(('<tr><td><code>{0}</code></td><td>{1}</td><td>{2}</td><td><code>{3}</code></td></tr>' -f (ConvertTo-BackupReportHtmlEncoded $file.relativePath), (ConvertTo-BackupReportHtmlEncoded $file.lengthText), (ConvertTo-BackupReportHtmlEncoded $file.hashAlgorithm), (ConvertTo-BackupReportHtmlEncoded $file.hash)))
    }
    $rows.Add('</tbody></table>')
    $rows.Add('<h2>Errors</h2>')
    $rows.Add('<table><thead><tr><th>Scope</th><th>Code</th><th>Message</th></tr></thead><tbody>')
    if (@($Report.errors).Count -eq 0) {
        $rows.Add('<tr><td colspan="3" class="ok">None</td></tr>')
    }
    else {
        foreach ($errorItem in @($Report.errors)) {
            $rows.Add(('<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f (ConvertTo-BackupReportHtmlEncoded $errorItem.scope), (ConvertTo-BackupReportHtmlEncoded $errorItem.code), (ConvertTo-BackupReportHtmlEncoded $errorItem.message)))
        }
    }
    $rows.Add('</tbody></table>')
    $rows.Add('</body></html>')

    return ($rows.ToArray() -join [Environment]::NewLine)
}

function Save-BackupAuditReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Report,
        [Parameter(Mandatory)]
        [object]$Plan,
        [switch]$DryRun
    )

    $files = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-BackupReportObjectValue -InputObject $Plan -Name 'files' -DefaultValue @())) {
        $format = [string](Get-BackupReportObjectValue -InputObject $file -Name 'format')
        $path = [string](Get-BackupReportObjectValue -InputObject $file -Name 'path')
        $entry = [ordered]@{
            format        = $format
            path          = $path
            fileName      = [string](Get-BackupReportObjectValue -InputObject $file -Name 'fileName')
            contentType   = [string](Get-BackupReportObjectValue -InputObject $file -Name 'contentType')
            written       = $false
            sizeBytes     = $null
            hashAlgorithm = $null
            hash          = $null
            error         = $null
        }

        try {
            if ($DryRun) {
                $entry.error = 'DryRun'
                $files.Add([PSCustomObject]$entry)
                continue
            }
            if ([string]::IsNullOrWhiteSpace($path)) {
                throw "Report path for format '$format' is empty."
            }

            $directory = Split-Path -Path $path -Parent
            if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }

            switch ($format) {
                'Json' {
                    Write-RenderKitJsonFileAtomic `
                        -Value $Report `
                        -Path $path `
                        -Depth 60 |
                        Out-Null
                }
                'Html' {
                    Set-Content `
                        -LiteralPath $path `
                        -Value (ConvertTo-BackupAuditReportHtml -Report $Report) `
                        -Encoding UTF8
                }
                'Text' {
                    Set-Content `
                        -LiteralPath $path `
                        -Value (ConvertTo-BackupAuditReportText -Report $Report) `
                        -Encoding UTF8
                }
                default {
                    throw "Report format '$format' is not supported."
                }
            }

            $item = Get-Item -LiteralPath $path -ErrorAction Stop
            $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop
            $entry.written = $true
            $entry.sizeBytes = [int64]$item.Length
            $entry.hashAlgorithm = 'SHA256'
            $entry.hash = [string]$hash.Hash
        }
        catch {
            $entry.error = $_.Exception.Message
        }

        $files.Add([PSCustomObject]$entry)
    }

    $fileArray = @($files.ToArray())
    return [PSCustomObject]@{
        schemaVersion  = '1.0'
        generatedAtUtc = [string]$Report.generatedAtUtc
        state          = if (@($fileArray | Where-Object { -not [bool]$_.written -and [string]$_.error -ne 'DryRun' }).Count -eq 0) { 'Written' } else { 'Failed' }
        dryRun         = [bool]$DryRun
        formats        = @($fileArray | ForEach-Object { [string]$_.format })
        files          = @($fileArray)
        summary        = [PSCustomObject]@{
            requestedCount = $fileArray.Count
            writtenCount   = @($fileArray | Where-Object { [bool]$_.written }).Count
            failedCount    = @($fileArray | Where-Object { -not [bool]$_.written -and [string]$_.error -ne 'DryRun' }).Count
        }
    }
}
