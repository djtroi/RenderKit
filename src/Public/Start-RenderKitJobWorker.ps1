function Start-RenderKitJobWorker {
    [CmdletBinding()]
    param(
        [string]$WorkerId,
        [string]$JobType = 'BackupProject',
        [string]$QueueName = 'backup',
        [ValidateRange(1, 3600)]
        [int]$PollIntervalSeconds = 5,
        [ValidateRange(1, 86400)]
        [int]$LeaseSeconds = 300,
        [ValidateRange(0, 1000000)]
        [int]$MaxJobs = 0,
        [switch]$RunOnce,
        [switch]$Detached,
        [string]$LogPath
    )

    $normalizedWorkerId = New-RenderKitWorkerId -WorkerId $WorkerId
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = Get-RenderKitWorkerLogPath -WorkerId $normalizedWorkerId
    }

    if ($Detached) {
        $modulePath = Join-Path -Path $script:RenderKitModuleRoot -ChildPath 'RenderKit.psd1'
        $quote = {
            param([string]$Value)
            "'" + (($Value -replace "'", "''")) + "'"
        }
        $commandParts = @(
            "Import-Module $(& $quote $modulePath) -Force",
            ("Start-RenderKitJobWorker -WorkerId {0} -JobType {1} -QueueName {2} -PollIntervalSeconds {3} -LeaseSeconds {4} -LogPath {5}" -f
                (& $quote $normalizedWorkerId),
                (& $quote $JobType),
                (& $quote $QueueName),
                [int]$PollIntervalSeconds,
                [int]$LeaseSeconds,
                (& $quote $LogPath))
        )
        if ($MaxJobs -gt 0) {
            $commandParts[1] += " -MaxJobs $([int]$MaxJobs)"
        }
        if ($RunOnce) {
            $commandParts[1] += ' -RunOnce'
        }

        $processPath = (Get-Process -Id $PID).Path
        $processName = if ([string]::IsNullOrWhiteSpace($processPath)) {
            $null
        }
        else {
            [System.IO.Path]::GetFileNameWithoutExtension($processPath)
        }
        if ($processName -notin @('pwsh', 'powershell')) {
            $powerShellCommand = @(
                Get-Command `
                    -Name @('pwsh', 'powershell') `
                    -CommandType Application `
                    -ErrorAction SilentlyContinue
            ) | Select-Object -First 1
            if (-not $powerShellCommand) {
                throw 'A PowerShell executable is required to start a detached RenderKit worker.'
            }
            $processPath = [string]$powerShellCommand.Source
        }
        $argumentList = @('-NoProfile')
        if ((Get-RenderKitPlatform) -eq 'Windows') {
            $argumentList += @('-ExecutionPolicy', 'Bypass')
        }
        $argumentList += @('-Command', ($commandParts -join '; '))
        $startParameters = @{
            FilePath     = $processPath
            ArgumentList = $argumentList
            PassThru     = $true
        }
        if ((Get-RenderKitPlatform) -eq 'Windows') {
            $startParameters.WindowStyle = 'Hidden'
        }

        $process = Start-Process @startParameters
        $state = New-RenderKitWorkerState `
            -WorkerId $normalizedWorkerId `
            -JobType $JobType `
            -QueueName $QueueName `
            -LogPath $LogPath `
            -Status Starting
        $state.processId = [int]$process.Id
        Save-RenderKitWorkerState -State $state | Out-Null
        Write-RenderKitWorkerLogEntry `
            -WorkerId $normalizedWorkerId `
            -LogPath $LogPath `
            -Message ("Detached worker process '{0}' started." -f $process.Id) |
            Out-Null

        return [PSCustomObject]@{
            workerId   = $normalizedWorkerId
            status     = 'Starting'
            detached   = $true
            processId  = [int]$process.Id
            statePath  = Get-RenderKitWorkerStatePath -WorkerId $normalizedWorkerId
            logPath    = $LogPath
            jobType    = $JobType
            queueName  = $QueueName
        }
    }

    Invoke-RenderKitLocalWorkerLoop `
        -WorkerId $normalizedWorkerId `
        -JobType $JobType `
        -QueueName $QueueName `
        -PollIntervalSeconds $PollIntervalSeconds `
        -LeaseSeconds $LeaseSeconds `
        -MaxJobs $MaxJobs `
        -RunOnce:$RunOnce `
        -LogPath $LogPath
}

Register-RenderKitFunction -Name 'Start-RenderKitJobWorker'
