function Get-RenderKitMediaInfoBundleRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return Join-Path `
        -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/ThirdParty/MediaInfo'
}

function Get-RenderKitMediaInfoRuntimeIdentifier {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $os = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        'win'
    }
    else {
        try {
            if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                    [System.Runtime.InteropServices.OSPlatform]::OSX)) {
                'osx'
            }
            elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                    [System.Runtime.InteropServices.OSPlatform]::Linux)) {
                'linux'
            }
            else {
                'unknown'
            }
        }
        catch {
            'unknown'
        }
    }

    $architecture = try {
        [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    }
    catch {
        [string]$env:PROCESSOR_ARCHITECTURE
    }

    return ConvertTo-RenderKitMediaInfoRuntimeIdentifier `
        -OperatingSystem $os `
        -Architecture $architecture
}

function ConvertTo-RenderKitMediaInfoRuntimeIdentifier {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$OperatingSystem,

        [Parameter(Mandatory)]
        [string]$Architecture
    )

    $os = switch -Regex ($OperatingSystem) {
        '^(Win|Windows|Win32NT)$' { 'win'; break }
        '^(OSX|macOS|Darwin)$' { 'osx'; break }
        '^(Linux|Unix)$' { 'linux'; break }
        default { $OperatingSystem.ToLowerInvariant() }
    }

    $arch = switch -Regex ($Architecture) {
        'Arm64|Aarch64|ARM64' { 'arm64'; break }
        'X64|AMD64|x86_64' { 'x64'; break }
        default { $Architecture.ToLowerInvariant() }
    }

    return '{0}-{1}' -f $os, $arch
}

function Read-RenderKitMediaInfoBundleManifest {
    [CmdletBinding()]
    param(
        [switch]$Reload
    )

    $manifestPath = Join-Path `
        -Path (Get-RenderKitMediaInfoBundleRoot) `
        -ChildPath 'manifest.json'

    if (-not $Reload -and
        $script:RenderKitMediaInfoBundleManifest -and
        $script:RenderKitMediaInfoBundleManifestPath -eq $manifestPath) {
        return $script:RenderKitMediaInfoBundleManifest
    }

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $null
    }

    $manifest = Read-RenderKitJsonFile -Path $manifestPath -MaximumBytes 1048576
    $script:RenderKitMediaInfoBundleManifest = $manifest
    $script:RenderKitMediaInfoBundleManifestPath = $manifestPath
    return $manifest
}

function Get-RenderKitMediaInfoBundleRuntime {
    [CmdletBinding()]
    param(
        [string]$RuntimeIdentifier = (Get-RenderKitMediaInfoRuntimeIdentifier)
    )

    $manifest = Read-RenderKitMediaInfoBundleManifest
    if (-not $manifest) {
        return $null
    }

    return @(
        $manifest.runtimeIdentifiers |
            Where-Object { [string]$_.rid -ieq $RuntimeIdentifier } |
            Select-Object -First 1
    )
}

function Test-RenderKitMediaInfoUsableFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    return [System.IO.Path]::GetFileName($Path) -ne '.gitkeep'
}

function New-RenderKitMediaInfoCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Native', 'Host', 'Cli')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [ValidateSet('Environment', 'Bundled', 'System')]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Path,

        [string]$DisplayName,

        [bool]$Available = $true
    )

    [PSCustomObject]@{
        Kind = $Kind
        Source = $Source
        Path = $Path
        DisplayName = if ([string]::IsNullOrWhiteSpace($DisplayName)) { $Path } else { $DisplayName }
        Available = [bool]$Available
    }
}

function Get-RenderKitMediaInfoSystemNativeName {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return @('MediaInfo.dll', 'libmediainfo.dll')
    }

    try {
        if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                [System.Runtime.InteropServices.OSPlatform]::OSX)) {
            return @('libmediainfo.dylib', 'libmediainfo.0.dylib')
        }
    }
    catch {
    }

    return @('libmediainfo.so', 'libmediainfo.so.0')
}

function Find-RenderKitMediaInfoSystemNativeLibrary {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $names = @(Get-RenderKitMediaInfoSystemNativeName)
    $directories = New-Object System.Collections.Generic.List[string]

    foreach ($pathEntry in @(([string]$env:PATH) -split [System.IO.Path]::PathSeparator)) {
        if (-not [string]::IsNullOrWhiteSpace($pathEntry) -and
            (Test-Path -LiteralPath $pathEntry -PathType Container)) {
            $directories.Add((Resolve-Path -LiteralPath $pathEntry).ProviderPath)
        }
    }

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not [string]::IsNullOrWhiteSpace($base)) {
                $candidateDir = Join-Path -Path $base -ChildPath 'MediaInfo'
                if (Test-Path -LiteralPath $candidateDir -PathType Container) {
                    $directories.Add((Resolve-Path -LiteralPath $candidateDir).ProviderPath)
                }
            }
        }
    }
    else {
        foreach ($candidateDir in @(
            '/usr/local/lib',
            '/usr/lib',
            '/usr/lib/x86_64-linux-gnu',
            '/usr/lib/aarch64-linux-gnu',
            '/opt/homebrew/lib',
            '/opt/local/lib'
        )) {
            if (Test-Path -LiteralPath $candidateDir -PathType Container) {
                $directories.Add($candidateDir)
            }
        }
    }

    foreach ($directory in @($directories.ToArray() | Select-Object -Unique)) {
        foreach ($name in $names) {
            $candidatePath = Join-Path -Path $directory -ChildPath $name
            if (Test-RenderKitMediaInfoUsableFile -Path $candidatePath) {
                return [System.IO.Path]::GetFullPath($candidatePath)
            }
        }
    }

    return $null
}

function Resolve-RenderKitMediaInfoReader {
    [CmdletBinding()]
    param()

    $bundleRoot = Get-RenderKitMediaInfoBundleRoot
    $runtime = Get-RenderKitMediaInfoBundleRuntime
    $nativeCandidates = New-Object System.Collections.Generic.List[object]
    $hostCandidates = New-Object System.Collections.Generic.List[object]
    $cliCandidates = New-Object System.Collections.Generic.List[object]

    $envNative = [string]$env:RENDERKIT_MEDIAINFO_LIBRARY
    if (-not [string]::IsNullOrWhiteSpace($envNative)) {
        $nativeCandidates.Add((New-RenderKitMediaInfoCandidate `
            -Kind Native `
            -Source Environment `
            -Path ([System.IO.Path]::GetFullPath($envNative)) `
            -Available (Test-RenderKitMediaInfoUsableFile -Path $envNative)))
    }

    if ($runtime -and -not [string]::IsNullOrWhiteSpace([string]$runtime.nativeLibraryRelativePath)) {
        $nativePath = Join-Path `
            -Path $bundleRoot `
            -ChildPath ([string]$runtime.nativeLibraryRelativePath)
        if (Test-RenderKitMediaInfoUsableFile -Path $nativePath) {
            $nativeCandidates.Add((New-RenderKitMediaInfoCandidate `
                -Kind Native `
                -Source Bundled `
                -Path ([System.IO.Path]::GetFullPath($nativePath))))
        }
    }

    $systemNativePath = if ([string]$env:RENDERKIT_MEDIAINFO_DISABLE_SYSTEM_NATIVE -eq '1') {
        $null
    }
    else {
        Find-RenderKitMediaInfoSystemNativeLibrary
    }
    if (-not [string]::IsNullOrWhiteSpace($systemNativePath)) {
        $nativeCandidates.Add((New-RenderKitMediaInfoCandidate `
            -Kind Native `
            -Source System `
            -Path $systemNativePath))
    }

    $envHost = [string]$env:RENDERKIT_MEDIAINFO_HOST
    if (-not [string]::IsNullOrWhiteSpace($envHost)) {
        $hostCandidates.Add((New-RenderKitMediaInfoCandidate `
            -Kind Host `
            -Source Environment `
            -Path ([System.IO.Path]::GetFullPath($envHost)) `
            -Available (Test-RenderKitMediaInfoUsableFile -Path $envHost)))
    }

    $envCli = [string]$env:RENDERKIT_MEDIAINFO_PATH
    if (-not [string]::IsNullOrWhiteSpace($envCli)) {
        $cliCandidates.Add((New-RenderKitMediaInfoCandidate `
            -Kind Cli `
            -Source Environment `
            -Path ([System.IO.Path]::GetFullPath($envCli)) `
            -Available (Test-RenderKitMediaInfoUsableFile -Path $envCli)))
    }

    if ($runtime -and -not [string]::IsNullOrWhiteSpace([string]$runtime.cliRelativePath)) {
        $cliPath = Join-Path `
            -Path $bundleRoot `
            -ChildPath ([string]$runtime.cliRelativePath)
        if (Test-RenderKitMediaInfoUsableFile -Path $cliPath) {
            $cliCandidates.Add((New-RenderKitMediaInfoCandidate `
                -Kind Cli `
                -Source Bundled `
                -Path ([System.IO.Path]::GetFullPath($cliPath))))
        }
    }

    $systemCli = Get-RenderKitMetadataCommand -CommandName @('mediainfo', 'mediainfo.exe')
    if ($systemCli) {
        $cliCandidates.Add((New-RenderKitMediaInfoCandidate `
            -Kind Cli `
            -Source System `
            -Path ([string]$systemCli.Source) `
            -DisplayName ([string]$systemCli.Name)))
    }

    $firstNative = @($nativeCandidates | Where-Object { [bool]$_.Available } | Select-Object -First 1)
    $firstHost = @($hostCandidates | Where-Object { [bool]$_.Available } | Select-Object -First 1)
    $firstCli = @($cliCandidates | Where-Object { [bool]$_.Available } | Select-Object -First 1)
    $available = [bool]($firstNative -or $firstHost -or $firstCli)

    [PSCustomObject]@{
        Id = 'MediaInfo'
        Available = $available
        Mode = if ($firstNative) { 'Native' } elseif ($firstHost) { 'Host' } elseif ($firstCli) { 'Cli' } else { 'Unavailable' }
        Source = if ($firstNative) { [string]$firstNative.Source } elseif ($firstHost) { [string]$firstHost.Source } elseif ($firstCli) { [string]$firstCli.Source } else { $null }
        RuntimeIdentifier = Get-RenderKitMediaInfoRuntimeIdentifier
        NativeLibraryPath = if ($firstNative) { [string]$firstNative.Path } else { $null }
        CommandPath = if ($firstCli) { [string]$firstCli.Path } else { $null }
        CommandName = if ($firstCli) { [string]$firstCli.DisplayName } else { $null }
        HostPath = if ($firstHost) { [string]$firstHost.Path } else { $null }
        NativeCandidates = @($nativeCandidates.ToArray())
        HostCandidates = @($hostCandidates.ToArray())
        CliCandidates = @($cliCandidates.ToArray())
    }
}

function ConvertTo-RenderKitCSharpStringLiteral {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    return '"' + (
        $Value.
            Replace('\', '\\').
            Replace('"', '\"').
            Replace("`r", '\r').
            Replace("`n", '\n')
    ) + '"'
}

function Get-RenderKitMediaInfoNativeBridgeTypeName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$LibraryPath
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($LibraryPath.ToLowerInvariant())
        $hash = $sha256.ComputeHash($bytes)
        $suffix = (($hash | Select-Object -First 8 | ForEach-Object { $_.ToString('x2') }) -join '')
        return 'RenderKitMediaInfoNativeBridge_{0}' -f $suffix
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-RenderKitLoadedType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FullName
    )

    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        $type = $assembly.GetType($FullName, $false, $false)
        if ($type) {
            return $type
        }
    }

    return $null
}

function Get-RenderKitMediaInfoNativeBridgeType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LibraryPath
    )

    if (-not $script:RenderKitMediaInfoNativeBridgeTypeCache) {
        $script:RenderKitMediaInfoNativeBridgeTypeCache = @{}
    }
    if ($script:RenderKitMediaInfoNativeBridgeTypeCache.ContainsKey($LibraryPath)) {
        $cachedName = [string]$script:RenderKitMediaInfoNativeBridgeTypeCache[$LibraryPath]
        $cachedType = Get-RenderKitLoadedType -FullName $cachedName
        if ($cachedType) {
            return $cachedType
        }
    }

    $className = Get-RenderKitMediaInfoNativeBridgeTypeName -LibraryPath $LibraryPath
    $fullName = 'RenderKit.Native.{0}' -f $className
    $existingType = Get-RenderKitLoadedType -FullName $fullName
    if ($existingType) {
        $script:RenderKitMediaInfoNativeBridgeTypeCache[$LibraryPath] = $fullName
        return $existingType
    }

    $libraryLiteral = ConvertTo-RenderKitCSharpStringLiteral -Value $LibraryPath
    $source = @"
using System;
using System.Runtime.InteropServices;

namespace RenderKit.Native
{
    public static class $className
    {
        [DllImport($libraryLiteral, EntryPoint = "MediaInfo_New")]
        private static extern IntPtr MediaInfo_New();

        [DllImport($libraryLiteral, EntryPoint = "MediaInfo_Delete")]
        private static extern void MediaInfo_Delete(IntPtr handle);

        [DllImport($libraryLiteral, EntryPoint = "MediaInfo_Close")]
        private static extern void MediaInfo_Close(IntPtr handle);

        [DllImport($libraryLiteral, EntryPoint = "MediaInfo_Open")]
        private static extern IntPtr MediaInfo_Open(IntPtr handle, [MarshalAs(UnmanagedType.LPWStr)] string fileName);

        [DllImport($libraryLiteral, EntryPoint = "MediaInfoA_Open")]
        private static extern IntPtr MediaInfoA_Open(IntPtr handle, IntPtr fileName);

        [DllImport($libraryLiteral, EntryPoint = "MediaInfo_Inform")]
        private static extern IntPtr MediaInfo_Inform(IntPtr handle, IntPtr reserved);

        [DllImport($libraryLiteral, EntryPoint = "MediaInfoA_Inform")]
        private static extern IntPtr MediaInfoA_Inform(IntPtr handle, IntPtr reserved);

        [DllImport($libraryLiteral, EntryPoint = "MediaInfo_Option")]
        private static extern IntPtr MediaInfo_Option(IntPtr handle, [MarshalAs(UnmanagedType.LPWStr)] string option, [MarshalAs(UnmanagedType.LPWStr)] string value);

        [DllImport($libraryLiteral, EntryPoint = "MediaInfoA_Option")]
        private static extern IntPtr MediaInfoA_Option(IntPtr handle, IntPtr option, IntPtr value);

        private static bool MustUseAnsi
        {
            get
            {
                PlatformID platform = Environment.OSVersion.Platform;
                return platform == PlatformID.Unix || platform == PlatformID.MacOSX;
            }
        }

        public static string ReadJson(string fileName, string appVersion)
        {
            IntPtr handle = MediaInfo_New();
            if (handle == IntPtr.Zero)
            {
                throw new InvalidOperationException("MediaInfo_New returned a null handle.");
            }

            try
            {
                Option(handle, "Internet", "No");
                Option(handle, "Complete", "1");
                Option(handle, "Output", "JSON");
                Option(handle, "Info_Version", "0.0.0.0;RenderKit;" + appVersion);

                IntPtr opened = Open(handle, fileName);
                if (opened == IntPtr.Zero)
                {
                    throw new InvalidOperationException("MediaInfo_Open returned 0 for the input file.");
                }

                string json = Inform(handle);
                if (String.IsNullOrWhiteSpace(json))
                {
                    throw new InvalidOperationException("MediaInfo_Inform returned an empty response.");
                }
                return json;
            }
            finally
            {
                try
                {
                    MediaInfo_Close(handle);
                }
                finally
                {
                    MediaInfo_Delete(handle);
                }
            }
        }

        private static IntPtr Open(IntPtr handle, string fileName)
        {
            if (!MustUseAnsi)
            {
                return MediaInfo_Open(handle, fileName);
            }

            IntPtr fileNamePtr = Marshal.StringToHGlobalAnsi(fileName);
            try
            {
                return MediaInfoA_Open(handle, fileNamePtr);
            }
            finally
            {
                Marshal.FreeHGlobal(fileNamePtr);
            }
        }

        private static string Inform(IntPtr handle)
        {
            if (!MustUseAnsi)
            {
                return Marshal.PtrToStringUni(MediaInfo_Inform(handle, IntPtr.Zero));
            }

            return Marshal.PtrToStringAnsi(MediaInfoA_Inform(handle, IntPtr.Zero));
        }

        private static string Option(IntPtr handle, string option, string value)
        {
            if (!MustUseAnsi)
            {
                return Marshal.PtrToStringUni(MediaInfo_Option(handle, option, value));
            }

            IntPtr optionPtr = Marshal.StringToHGlobalAnsi(option);
            IntPtr valuePtr = Marshal.StringToHGlobalAnsi(value);
            try
            {
                return Marshal.PtrToStringAnsi(MediaInfoA_Option(handle, optionPtr, valuePtr));
            }
            finally
            {
                Marshal.FreeHGlobal(optionPtr);
                Marshal.FreeHGlobal(valuePtr);
            }
        }
    }
}
"@

    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
    $type = Get-RenderKitLoadedType -FullName $fullName
    if (-not $type) {
        throw "MediaInfo native bridge type '$fullName' could not be loaded."
    }

    $script:RenderKitMediaInfoNativeBridgeTypeCache[$LibraryPath] = $fullName
    return $type
}

function Invoke-RenderKitMediaInfoNativeMetadataRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$LibraryPath
    )

    $type = Get-RenderKitMediaInfoNativeBridgeType -LibraryPath $LibraryPath
    $method = $type.GetMethod('ReadJson')
    if (-not $method) {
        throw "MediaInfo native bridge type '$($type.FullName)' does not expose ReadJson."
    }

    try {
        $json = [string]$method.Invoke($null, @($Path, [string]$script:RenderKitModuleVersion))
    }
    catch {
        $exception = $_.Exception
        while ($exception.InnerException) {
            $exception = $exception.InnerException
        }
        throw $exception
    }

    return $json | ConvertFrom-Json -ErrorAction Stop
}
