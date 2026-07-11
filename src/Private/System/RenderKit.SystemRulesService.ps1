function Test-RenderKitObjectProperty {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $false
    }

    return [bool](@($InputObject.PSObject.Properties |
            Where-Object { $_.Name -eq $Name }).Count -gt 0)
}

function Get-RenderKitSystemRuleValue {
    [CmdletBinding()]
    param(
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if (Test-RenderKitObjectProperty -InputObject $InputObject -Name $Name) {
        return $InputObject.$Name
    }

    return $DefaultValue
}

function New-RenderKitSystemRulesPolicy {
    [CmdletBinding()]
    param(
        [bool]$RequireIdle = $false,
        [ValidateRange(0, 1440)]
        [int]$MinIdleMinutes = 10,
        [bool]$AllowOnBattery = $false,
        [bool]$ThermalThrottleEnabled = $true,
        [ValidateRange(1, 100)]
        [int]$MaxCpuPercent = 90,
        [ValidateRange(1, 100)]
        [int]$MaxGpuPercent = 95,
        [ValidateRange(1, 100)]
        [int]$MaxDiskActivePercent = 90,
        [ValidateRange(1, 120)]
        [int]$MaxTemperatureCelsius = 85,
        [string]$AllowedStartTime,
        [string]$AllowedEndTime,
        [ValidateRange(1, 3600)]
        [int]$PollIntervalSeconds = 5
    )

    $scheduleEnabled = -not [string]::IsNullOrWhiteSpace($AllowedStartTime) -and
        -not [string]::IsNullOrWhiteSpace($AllowedEndTime)

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        enabled       = $true
        source        = 'BestEffortHostSample'
        pollIntervalSeconds = [int]$PollIntervalSeconds
        cpu           = [PSCustomObject]@{
            enabled    = $true
            maxPercent = [int]$MaxCpuPercent
            action     = 'Throttle'
        }
        gpu           = [PSCustomObject]@{
            enabled    = $true
            maxPercent = [int]$MaxGpuPercent
            action     = 'Throttle'
        }
        disk          = [PSCustomObject]@{
            enabled    = $true
            maxActivePercent = [int]$MaxDiskActivePercent
            action     = 'Throttle'
        }
        temperature   = [PSCustomObject]@{
            enabled    = [bool]$ThermalThrottleEnabled
            maxCelsius = [int]$MaxTemperatureCelsius
            action     = 'PauseOrWait'
        }
        battery       = [PSCustomObject]@{
            enabled    = -not [bool]$AllowOnBattery
            requireAC  = -not [bool]$AllowOnBattery
            minBatteryPercent = 20
            action     = 'PauseOrWait'
        }
        userIdle      = [PSCustomObject]@{
            enabled    = [bool]$RequireIdle
            minIdleSeconds = [int]($MinIdleMinutes * 60)
            action     = 'PauseOrWait'
        }
        schedule      = [PSCustomObject]@{
            enabled    = [bool]$scheduleEnabled
            startTime  = $AllowedStartTime
            endTime    = $AllowedEndTime
            timezone   = 'Local'
            action     = 'PauseOrWait'
        }
        throttling    = [PSCustomObject]@{
            enabled           = $true
            mode              = 'ReduceWorkerLimit'
            minWorkers        = 1
            pauseWhenBlocked  = $true
            throttleStepPercent = 50
        }
    }
}

function Get-RenderKitCpuPercentSample {
    [CmdletBinding()]
    [OutputType([System.Nullable[double]])]
    param()

    try {
        if (Get-Command -Name Get-Counter -ErrorAction SilentlyContinue) {
            $counter = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
            return [Math]::Round([double]$counter.CounterSamples[0].CookedValue, 2)
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-RenderKitBatterySample {
    [CmdletBinding()]
    param()

    try {
        if ((Get-RenderKitPlatform) -ne 'Windows' -or
            -not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{
                available = $false
                onBattery = $null
                percent   = $null
                status    = 'Unknown'
            }
        }

        $batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
        if ($batteries.Count -eq 0) {
            return [PSCustomObject]@{
                available = $false
                onBattery = $false
                percent   = $null
                status    = 'NoBattery'
            }
        }

        $lowestPercent = @($batteries |
            ForEach-Object { if ($null -ne $_.EstimatedChargeRemaining) { [int]$_.EstimatedChargeRemaining } } |
            Sort-Object |
            Select-Object -First 1)
        $onBattery = @($batteries | Where-Object {
                # BatteryStatus 1 = Discharging, 2 = AC, other values are treated as unknown/not AC.
                [int]$_.BatteryStatus -eq 1
            }).Count -gt 0

        return [PSCustomObject]@{
            available = $true
            onBattery = [bool]$onBattery
            percent   = if ($lowestPercent.Count -gt 0) { [int]$lowestPercent[0] } else { $null }
            status    = if ($onBattery) { 'Discharging' } else { 'AC' }
        }
    }
    catch {
        return [PSCustomObject]@{
            available = $false
            onBattery = $null
            percent   = $null
            status    = 'Unknown'
        }
    }
}

function Get-RenderKitUserIdleSeconds {
    [CmdletBinding()]
    [OutputType([System.Nullable[double]])]
    param()

    try {
        if ((Get-RenderKitPlatform) -ne 'Windows') {
            return $null
        }
        if (-not ('RenderKitLastInputInfo' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RenderKitLastInputInfo {
    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static double GetIdleSeconds() {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref info)) {
            return -1;
        }
        uint tickCount = (uint)Environment.TickCount;
        return (tickCount - info.dwTime) / 1000.0;
    }
}
'@ -ErrorAction Stop
        }

        $seconds = [RenderKitLastInputInfo]::GetIdleSeconds()
        if ($seconds -lt 0) {
            return $null
        }

        return [Math]::Round([double]$seconds, 1)
    }
    catch {
        return $null
    }
}

function Get-RenderKitSystemMetricSample {
    [CmdletBinding()]
    param(
        [object]$Override
    )

    if ($Override) {
        return $Override
    }

    return [PSCustomObject]@{
        sampledAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
        cpuPercent         = Get-RenderKitCpuPercentSample
        gpuPercent         = $null
        diskActivePercent  = $null
        temperatureCelsius = $null
        battery            = Get-RenderKitBatterySample
        userIdleSeconds    = Get-RenderKitUserIdleSeconds
        localTime          = (Get-Date).ToString('HH:mm')
    }
}

function Test-RenderKitTimeInWindow {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentTime,
        [Parameter(Mandatory)]
        [string]$StartTime,
        [Parameter(Mandatory)]
        [string]$EndTime
    )

    $current = [TimeSpan]::Parse($CurrentTime)
    $start = [TimeSpan]::Parse($StartTime)
    $end = [TimeSpan]::Parse($EndTime)

    if ($start -eq $end) {
        return $true
    }
    if ($start -lt $end) {
        return [bool]($current -ge $start -and $current -le $end)
    }

    return [bool]($current -ge $start -or $current -le $end)
}

function Add-RenderKitSystemRuleIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IList]$List,
        [Parameter(Mandatory)]
        [string]$Rule,
        [Parameter(Mandatory)]
        [string]$Reason,
        [object]$Actual,
        [object]$Limit,
        [ValidateSet('Block', 'Throttle', 'Unknown')]
        [string]$Kind = 'Block'
    )

    [void]$List.Add([PSCustomObject]@{
            rule   = $Rule
            reason = $Reason
            actual = $Actual
            limit  = $Limit
            kind   = $Kind
        })
}

function Test-RenderKitSystemRules {
    [CmdletBinding()]
    param(
        [object]$Rules,
        [object]$Sample,
        [ValidateRange(1, 64)]
        [int]$BaseWorkerLimit = 1
    )

    if (-not $Rules -or -not [bool](Get-RenderKitSystemRuleValue -InputObject $Rules -Name enabled -DefaultValue $false)) {
        return [PSCustomObject]@{
            canRun               = $true
            shouldThrottle       = $false
            throttlePercent      = 100
            effectiveWorkerLimit = [Math]::Max(1, [int]$BaseWorkerLimit)
            waitSeconds          = 0
            blockedBy            = @()
            throttledBy          = @()
            unknownMetrics       = @()
            sample               = $Sample
        }
    }

    $sample = Get-RenderKitSystemMetricSample -Override $Sample
    $blocked = New-Object System.Collections.ArrayList
    $throttled = New-Object System.Collections.ArrayList
    $unknown = New-Object System.Collections.ArrayList
    $throttlePercent = 100

    $cpuRule = Get-RenderKitSystemRuleValue -InputObject $Rules -Name cpu
    if ($cpuRule -and [bool](Get-RenderKitSystemRuleValue -InputObject $cpuRule -Name enabled -DefaultValue $false)) {
        $cpu = Get-RenderKitSystemRuleValue -InputObject $sample -Name cpuPercent
        if ($null -eq $cpu) {
            Add-RenderKitSystemRuleIssue -List $unknown -Rule 'CPU' -Reason 'CpuMetricUnavailable' -Kind Unknown
        }
        elseif ([double]$cpu -gt [double]$cpuRule.maxPercent) {
            Add-RenderKitSystemRuleIssue -List $throttled -Rule 'CPU' -Reason 'CpuAboveLimit' -Actual ([double]$cpu) -Limit ([double]$cpuRule.maxPercent) -Kind Throttle
            $throttlePercent = [Math]::Min($throttlePercent, [int]$Rules.throttling.throttleStepPercent)
        }
    }

    $gpuRule = Get-RenderKitSystemRuleValue -InputObject $Rules -Name gpu
    if ($gpuRule -and [bool](Get-RenderKitSystemRuleValue -InputObject $gpuRule -Name enabled -DefaultValue $false)) {
        $gpu = Get-RenderKitSystemRuleValue -InputObject $sample -Name gpuPercent
        if ($null -eq $gpu) {
            Add-RenderKitSystemRuleIssue -List $unknown -Rule 'GPU' -Reason 'GpuMetricUnavailable' -Kind Unknown
        }
        elseif ([double]$gpu -gt [double]$gpuRule.maxPercent) {
            Add-RenderKitSystemRuleIssue -List $throttled -Rule 'GPU' -Reason 'GpuAboveLimit' -Actual ([double]$gpu) -Limit ([double]$gpuRule.maxPercent) -Kind Throttle
            $throttlePercent = [Math]::Min($throttlePercent, [int]$Rules.throttling.throttleStepPercent)
        }
    }

    $diskRule = Get-RenderKitSystemRuleValue -InputObject $Rules -Name disk
    if ($diskRule -and [bool](Get-RenderKitSystemRuleValue -InputObject $diskRule -Name enabled -DefaultValue $false)) {
        $disk = Get-RenderKitSystemRuleValue -InputObject $sample -Name diskActivePercent
        if ($null -eq $disk) {
            Add-RenderKitSystemRuleIssue -List $unknown -Rule 'Disk' -Reason 'DiskMetricUnavailable' -Kind Unknown
        }
        elseif ([double]$disk -gt [double]$diskRule.maxActivePercent) {
            Add-RenderKitSystemRuleIssue -List $throttled -Rule 'Disk' -Reason 'DiskAboveLimit' -Actual ([double]$disk) -Limit ([double]$diskRule.maxActivePercent) -Kind Throttle
            $throttlePercent = [Math]::Min($throttlePercent, [int]$Rules.throttling.throttleStepPercent)
        }
    }

    $temperatureRule = Get-RenderKitSystemRuleValue -InputObject $Rules -Name temperature
    if ($temperatureRule -and [bool](Get-RenderKitSystemRuleValue -InputObject $temperatureRule -Name enabled -DefaultValue $false)) {
        $temperature = Get-RenderKitSystemRuleValue -InputObject $sample -Name temperatureCelsius
        if ($null -eq $temperature) {
            Add-RenderKitSystemRuleIssue -List $unknown -Rule 'Temperature' -Reason 'TemperatureMetricUnavailable' -Kind Unknown
        }
        elseif ([double]$temperature -gt [double]$temperatureRule.maxCelsius) {
            Add-RenderKitSystemRuleIssue -List $blocked -Rule 'Temperature' -Reason 'TemperatureAboveLimit' -Actual ([double]$temperature) -Limit ([double]$temperatureRule.maxCelsius)
        }
    }

    $batteryRule = Get-RenderKitSystemRuleValue -InputObject $Rules -Name battery
    if ($batteryRule -and [bool](Get-RenderKitSystemRuleValue -InputObject $batteryRule -Name enabled -DefaultValue $false)) {
        $battery = Get-RenderKitSystemRuleValue -InputObject $sample -Name battery
        if (-not $battery -or $null -eq (Get-RenderKitSystemRuleValue -InputObject $battery -Name onBattery)) {
            Add-RenderKitSystemRuleIssue -List $unknown -Rule 'Battery' -Reason 'BatteryMetricUnavailable' -Kind Unknown
        }
        elseif ([bool]$batteryRule.requireAC -and [bool]$battery.onBattery) {
            Add-RenderKitSystemRuleIssue -List $blocked -Rule 'Battery' -Reason 'OnBatteryPower' -Actual 'OnBattery' -Limit 'AC'
        }
    }

    $idleRule = Get-RenderKitSystemRuleValue -InputObject $Rules -Name userIdle
    if ($idleRule -and [bool](Get-RenderKitSystemRuleValue -InputObject $idleRule -Name enabled -DefaultValue $false)) {
        $idleSeconds = Get-RenderKitSystemRuleValue -InputObject $sample -Name userIdleSeconds
        if ($null -eq $idleSeconds) {
            Add-RenderKitSystemRuleIssue -List $unknown -Rule 'UserIdle' -Reason 'UserIdleMetricUnavailable' -Kind Unknown
        }
        elseif ([double]$idleSeconds -lt [double]$idleRule.minIdleSeconds) {
            Add-RenderKitSystemRuleIssue -List $blocked -Rule 'UserIdle' -Reason 'UserIdleBelowMinimum' -Actual ([double]$idleSeconds) -Limit ([double]$idleRule.minIdleSeconds)
        }
    }

    $scheduleRule = Get-RenderKitSystemRuleValue -InputObject $Rules -Name schedule
    if ($scheduleRule -and [bool](Get-RenderKitSystemRuleValue -InputObject $scheduleRule -Name enabled -DefaultValue $false)) {
        $localTime = Get-RenderKitSystemRuleValue -InputObject $sample -Name localTime -DefaultValue (Get-Date).ToString('HH:mm')
        if (-not (Test-RenderKitTimeInWindow -CurrentTime ([string]$localTime) -StartTime ([string]$scheduleRule.startTime) -EndTime ([string]$scheduleRule.endTime))) {
            Add-RenderKitSystemRuleIssue -List $blocked -Rule 'Schedule' -Reason 'OutsideAllowedTimeWindow' -Actual ([string]$localTime) -Limit ("{0}-{1}" -f $scheduleRule.startTime, $scheduleRule.endTime)
        }
    }

    $canRun = $blocked.Count -eq 0
    $minWorkers = if ($Rules.throttling -and $Rules.throttling.minWorkers) { [int]$Rules.throttling.minWorkers } else { 1 }
    $effectiveWorkerLimit = if ($canRun) {
        [Math]::Max($minWorkers, [Math]::Floor([double]$BaseWorkerLimit * ([double]$throttlePercent / 100.0)))
    }
    else {
        0
    }
    $waitSeconds = if ($Rules.pollIntervalSeconds) { [int]$Rules.pollIntervalSeconds } else { 5 }

    return [PSCustomObject]@{
        canRun               = [bool]$canRun
        shouldThrottle       = [bool]($canRun -and $throttled.Count -gt 0)
        throttlePercent      = [int]$throttlePercent
        effectiveWorkerLimit = [int]$effectiveWorkerLimit
        waitSeconds          = $waitSeconds
        blockedBy            = @($blocked.ToArray())
        throttledBy          = @($throttled.ToArray())
        unknownMetrics       = @($unknown.ToArray())
        sample               = $sample
    }
}
