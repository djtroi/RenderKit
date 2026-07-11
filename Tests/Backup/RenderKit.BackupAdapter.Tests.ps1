Describe 'RenderKit backup adapters' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -Force
    }

    AfterEach {
        foreach ($adapterId in @(
                'storage.test-memory',
                'verifier.test-memory',
                'encoder.test-command',
                'notifier.test-file',
                'storage.test-cold-start'
            )) {
            Remove-BackupAdapter `
                -Id $adapterId `
                -Force `
                -Confirm:$false `
                -ErrorAction SilentlyContinue |
                Out-Null
        }
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'publishes versioned contracts and built-in adapters for all four types' {
        $adapters = @(Get-BackupAdapter)

        $adapters.Id | Should -Contain 'storage.filesystem'
        $adapters.Id | Should -Contain 'encoder.ffmpeg'
        $adapters.Id | Should -Contain 'verifier.sha256'
        $adapters.Id | Should -Contain 'notifier.log'
        ($adapters | Where-Object Id -eq 'storage.filesystem').Operations |
            Should -Contain 'TestHealth'
        ($adapters | Where-Object Id -eq 'encoder.ffmpeg').Operations |
            Should -Contain 'BuildCommand'
        ($adapters | Select-Object -ExpandProperty ContractVersion -Unique) |
            Should -Be '1.0'

        $contracts = InModuleScope RenderKit {
            (Get-BackupAdapterContractCatalog).Values
        }
        $contracts.type | Should -Contain 'Storage'
        $contracts.type | Should -Contain 'Encoder'
        $contracts.type | Should -Contain 'Verifier'
        $contracts.type | Should -Contain 'Notifier'
    }

    It 'rejects adapters that do not satisfy their required operations' {
        {
            Register-BackupAdapter `
                -Id storage.test-memory `
                -Type Storage `
                -Name 'Incomplete storage' `
                -Version 1.0.0 `
                -Operations @{
                    TestHealth = { param($Context) $Context }
                }
        } | Should -Throw '*Write*'
    }

    It 'uses custom storage and verifier adapters for URI targets' {
        Register-BackupAdapter `
            -Id storage.test-memory `
            -Type Storage `
            -Name 'Test memory storage' `
            -Version 1.0.0 `
            -Alias Memory `
            -Capability @('Uri', 'Copy') `
            -Operations @{
                TestHealth = {
                    param($Context)
                    [PSCustomObject]@{
                        healthy   = $true
                        state     = 'Healthy'
                        reason    = 'TestAdapterReady'
                        canWrite  = $true
                        freeBytes = [int64]::MaxValue
                        error     = $null
                    }
                }
                Write = {
                    param($Context)
                    [PSCustomObject]@{
                        copied     = $true
                        targetPath = [string]$Context.targetPath
                        sizeBytes  = [int64]$Context.expectedSizeBytes
                    }
                }
            } |
            Out-Null
        Register-BackupAdapter `
            -Id verifier.test-memory `
            -Type Verifier `
            -Name 'Test memory verifier' `
            -Version 1.0.0 `
            -Capability Checksum `
            -Operations @{
                Verify = {
                    param($Context)
                    [PSCustomObject]@{
                        verified    = $true
                        targetHash  = [string]$Context.expectedHash
                        sizeBytes   = [int64]$Context.expectedSizeBytes
                        hashMatches = $true
                        sizeMatches = $true
                        error       = $null
                    }
                }
            } |
            Out-Null

        $sourcePath = Join-Path $TestDrive 'adapter-source.zip'
        Set-Content -LiteralPath $sourcePath -Value 'adapter-content' -Encoding UTF8
        $sourceItem = Get-Item -LiteralPath $sourcePath
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $result = InModuleScope RenderKit -Parameters @{
            SourcePath = $sourcePath
            SourceHash = $sourceHash
            SourceSize = [int64]$sourceItem.Length
        } {
            $tiers = ConvertTo-BackupProjectStorageTier `
                -StorageTier @(
                    @{
                        Id = 'tier-memory'
                        Name = 'Memory'
                        Profile = 'CloudS3'
                        Uri = 'memory://renderkit/archive'
                        Adapter = 'storage.test-memory'
                        VerifierAdapter = 'verifier.test-memory'
                        Required = $true
                    }
                )
            Invoke-BackupStorageTierCopyVerify `
                -SourcePath $SourcePath `
                -ArchivePath $SourcePath `
                -Tier $tiers[0] `
                -ExpectedHash $SourceHash `
                -ExpectedSizeBytes $SourceSize
        }

        $result.storageAdapterId | Should -Be 'storage.test-memory'
        $result.verifierAdapterId | Should -Be 'verifier.test-memory'
        $result.health.state | Should -Be 'Healthy'
        $result.targetPath | Should -Match '^memory://'
        $result.copied | Should -BeTrue
        $result.verified | Should -BeTrue
        $result.state | Should -Be 'Verified'
    }

    It 'uses a custom encoder adapter to resolve profiles and build chunk commands' {
        Register-BackupAdapter `
            -Id encoder.test-command `
            -Type Encoder `
            -Name 'Test command encoder' `
            -Version 1.2.0 `
            -Capability @('H264', 'ChunkEncoding') `
            -Operations @{
                ResolveProfile = {
                    param($Context)
                    [PSCustomObject]@{
                        name             = 'Test-H264'
                        container        = 'mp4'
                        videoCodec       = 'H264'
                        encoderDevice    = 'CPU'
                        encoderName      = 'test-h264'
                        qualityPreset    = [string]$Context.qualityPreset
                        qualityValue     = 23
                        audioProfile     = 'AAC_128'
                        encoderSelection = [PSCustomObject]@{
                            source = 'TestAdapter'
                            device = 'CPU'
                        }
                        videoArgs        = @()
                        audioArgs        = @()
                    }
                }
                BuildCommand = {
                    param($Context)
                    [PSCustomObject]@{
                        executable = 'test-encoder'
                        arguments  = @(
                            '--input',
                            [string]$Context.chunk.path,
                            '--output',
                            [string]$Context.outputPath
                        )
                    }
                }
            } |
            Out-Null

        $plan = InModuleScope RenderKit {
            $payload = [PSCustomObject]@{
                archive = [PSCustomObject]@{
                    mode = 'TranscodeAndArchive'
                    compressionPreset = 'Balanced'
                }
                encoding = [PSCustomObject]@{
                    adapterId = 'encoder.test-command'
                    videoCodec = 'H264'
                    encoderDevice = 'CPU'
                    qualityPreset = 'Balanced'
                    audioProfile = 'AAC_128'
                    proxy = [PSCustomObject]@{ enabled = $false }
                    preview = [PSCustomObject]@{ enabled = $false }
                }
                mediaAnalysis = [PSCustomObject]@{
                    files = @(
                        [PSCustomObject]@{
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Media\main.mp4'
                            mediaType = 'Video'
                            metadata = [PSCustomObject]@{
                                durationSeconds = 20.0
                                videoStreams = @([PSCustomObject]@{ index = 0; codec = 'h264' })
                                audioStreams = @()
                                hasVideo = $true
                                hasAudio = $false
                            }
                        }
                    )
                }
                chunkPlan = [PSCustomObject]@{
                    assets = @(
                        [PSCustomObject]@{
                            id = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Media\main.mp4'
                            mediaType = 'Video'
                        }
                    )
                    chunks = @(
                        [PSCustomObject]@{
                            id = 'chunk-main-000000'
                            assetId = 'asset-main'
                            relativePath = 'Media/main.mp4'
                            path = 'D:\Media\main.mp4'
                            index = 0
                            startSeconds = 0.0
                            durationSeconds = 20.0
                        }
                    )
                }
            }
            New-BackupEncodingPlan `
                -Job ([PSCustomObject]@{ id = 'adapter-encoder-job'; payload = $payload }) `
                -Payload $payload
        }

        $plan.encoderAdapter.id | Should -Be 'encoder.test-command'
        $plan.encoderAdapter.version | Should -Be '1.2.0'
        $plan.profile.adapterId | Should -Be 'encoder.test-command'
        $plan.commands[0].adapterId | Should -Be 'encoder.test-command'
        $plan.commands[0].executable | Should -Be 'test-encoder'
        $plan.commands[0].arguments | Should -Contain '--input'
    }

    It 'delivers structured events through a custom notifier adapter' {
        Register-BackupAdapter `
            -Id notifier.test-file `
            -Type Notifier `
            -Name 'Test file notifier' `
            -Version 1.0.0 `
            -Capability @('JobStarted', 'JobCompleted') `
            -Operations @{
                Notify = {
                    param($Context)
                    Add-Content `
                        -LiteralPath ([string]$Context.payload.notificationPath) `
                        -Value ([string]$Context.eventName)
                    [PSCustomObject]@{
                        delivered = $true
                        eventName = [string]$Context.eventName
                    }
                }
            } |
            Out-Null

        $notificationPath = Join-Path $TestDrive 'adapter-events.txt'
        $results = InModuleScope RenderKit -Parameters @{
            NotificationPath = $notificationPath
        } {
            $selection = New-BackupAdapterSelection `
                -Type Notifier `
                -RequestedName 'notifier.test-file' `
                -Required $false
            $job = [PSCustomObject]@{
                id = 'notifier-adapter-job'
                payload = [PSCustomObject]@{
                    notificationPath = $NotificationPath
                    adapters = [PSCustomObject]@{
                        notifiers = @($selection)
                    }
                }
            }
            @(
                Send-BackupAdapterNotification -Job $job -EventName JobStarted
                Send-BackupAdapterNotification -Job $job -EventName JobCompleted
            )
        }

        $results.state | Should -Not -Contain 'Failed'
        @(Get-Content -LiteralPath $notificationPath) |
            Should -Be @('JobStarted', 'JobCompleted')
    }

    It 'reloads a provider module from a persisted adapter plan' {
        $moduleName = 'RenderKit.TestColdStartAdapter'
        $moduleRoot = Join-Path $TestDrive $moduleName
        $modulePath = Join-Path $moduleRoot "$moduleName.psm1"
        New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
        @'
function Test-RenderKitColdStartStorageHealth {
    param($Context)
    [PSCustomObject]@{
        healthy = $true
        state = 'Healthy'
        target = [string]$Context.target
    }
}

function Write-RenderKitColdStartStorage {
    param($Context)
    [PSCustomObject]@{
        written = $true
        target = [string]$Context.target
    }
}

Register-BackupAdapter `
    -Id storage.test-cold-start `
    -Type Storage `
    -Name 'Cold-start storage' `
    -Version 1.0.0 `
    -ModuleName 'RenderKit.TestColdStartAdapter' `
    -Operations @{
        TestHealth = 'Test-RenderKitColdStartStorageHealth'
        Write = 'Write-RenderKitColdStartStorage'
    } `
    -Force |
    Out-Null

Export-ModuleMember -Function @(
    'Test-RenderKitColdStartStorageHealth',
    'Write-RenderKitColdStartStorage'
)
'@ | Set-Content -LiteralPath $modulePath -Encoding UTF8

        $originalModulePath = $env:PSModulePath
        try {
            $env:PSModulePath = @(
                $TestDrive,
                $originalModulePath
            ) -join [System.IO.Path]::PathSeparator
            Import-Module -Name $moduleName -Force

            $plan = InModuleScope RenderKit {
                New-BackupAdapterPlan `
                    -StorageTiers @(
                        [PSCustomObject]@{
                            id = 'cold-start-tier'
                            adapterId = 'storage.test-cold-start'
                            required = $true
                        }
                    )
            }
            $plan.storage[0].provider.moduleName |
                Should -Be $moduleName

            Remove-BackupAdapter `
                -Id storage.test-cold-start `
                -Force `
                -Confirm:$false |
                Out-Null
            Remove-Module -Name $moduleName -Force

            $result = InModuleScope RenderKit -Parameters @{
                AdapterPlan = $plan
            } {
                Import-BackupAdapterProvidersFromPlan -Plan $AdapterPlan |
                    Out-Null
                $adapter = Get-BackupAdapterDefinition `
                    -Type Storage `
                    -Name storage.test-cold-start
                Invoke-BackupAdapterOperation `
                    -Adapter $adapter `
                    -Operation TestHealth `
                    -Context ([PSCustomObject]@{ target = 'cold://archive' })
            }

            $result.healthy | Should -BeTrue
            $result.target | Should -Be 'cold://archive'
        }
        finally {
            Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
            $env:PSModulePath = $originalModulePath
        }
    }
}
