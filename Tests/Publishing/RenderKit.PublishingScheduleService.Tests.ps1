Describe 'RenderKit publishing schedule service' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:RenderKitModuleRoot = $repositoryRoot
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Publishing/RenderKit.PublishingScheduleService.ps1')
    }

    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        if (Test-Path -LiteralPath $env:RENDERKIT_HOME) {
            Remove-Item -LiteralPath $env:RENDERKIT_HOME -Recurse -Force
        }
        $script:RenderKitArtifactVersionCatalog = $null
    }

    AfterEach {
        $env:RENDERKIT_HOME = $null
    }

    It 'treats an absent store as an empty versioned schedule' {
        $schedule = Read-RenderKitPublishingSchedule

        $schedule.schemaVersion | Should -Be '1.0'
        @($schedule.publications).Count | Should -Be 0
        Test-RenderKitPublishingSchedule $schedule | Should -BeTrue
    }

    It 'creates records and returns range overlaps in stable order' {
        Add-RenderKitPublicationRecord -Publication (
            New-RenderKitPublicationRecord `
                -Title 'Second' `
                -Status Scheduled `
                -StartUtc '2026-07-10T12:00:00+02:00' `
                -EndUtc '2026-07-10T14:00:00+02:00' `
                -TimeZone 'Europe/Berlin'
        ) | Out-Null
        Add-RenderKitPublicationRecord -Publication (
            New-RenderKitPublicationRecord `
                -Title 'First overlap' `
                -Status Draft `
                -StartUtc '2026-07-09T22:00:00Z' `
                -EndUtc '2026-07-10T01:00:00Z' `
                -TimeZone UTC
        ) | Out-Null

        $records = @(Get-RenderKitPublicationRecordList `
            -FromUtc '2026-07-10T00:00:00Z' `
            -ToUtc '2026-07-11T00:00:00Z')

        $records.Count | Should -Be 2
        $records[0].title | Should -Be 'First overlap'
        $records[1].startUtc | Should -Be '2026-07-10T10:00:00.0000000+00:00'
    }

    It 'enforces revisions and allowed status transitions' {
        $created = Add-RenderKitPublicationRecord -Publication (
            New-RenderKitPublicationRecord `
                -Title 'Planned release' `
                -StartUtc '2026-07-10T10:00:00Z' `
                -TimeZone UTC
        )
        $scheduled = Update-RenderKitPublicationRecord `
            -Id $created.id `
            -ExpectedRevision 1 `
            -Changes @{ Status = 'Scheduled' }

        $scheduled.revision | Should -Be 2
        $scheduled.status | Should -Be 'Scheduled'
        {
            Update-RenderKitPublicationRecord `
                -Id $created.id `
                -ExpectedRevision 1 `
                -Changes @{ Title = 'Stale edit' }
        } | Should -Throw '*changed from revision*'
        {
            Update-RenderKitPublicationRecord `
                -Id $created.id `
                -ExpectedRevision 2 `
                -Changes @{ Status = 'Published' }
        } | Should -Throw '*cannot change*'
    }

    It 'rejects implicit timezones, invalid ranges, and oversized queries' {
        {
            New-RenderKitPublicationRecord `
                -Title 'No offset' `
                -StartUtc '2026-07-10T10:00:00' `
                -TimeZone UTC
        } | Should -Throw '*explicit UTC offset*'
        {
            New-RenderKitPublicationRecord `
                -Title 'Reverse range' `
                -StartUtc '2026-07-10T10:00:00Z' `
                -EndUtc '2026-07-10T09:00:00Z' `
                -TimeZone UTC
        } | Should -Throw '*later than StartUtc*'
        {
            Get-RenderKitPublicationRecordList `
                -FromUtc '2026-01-01T00:00:00Z' `
                -ToUtc '2027-02-01T00:00:00Z'
        } | Should -Throw '*at most 370 days*'
    }
}
