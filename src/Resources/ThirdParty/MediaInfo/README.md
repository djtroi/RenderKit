# MediaInfo Bundle

RenderKit bundles MediaInfoLib 26.01 as its primary metadata reader. Native
assets are selected by the current process runtime identifier (RID). A native
load or read failure does not stop metadata extraction: the reader continues
through an explicitly configured host and then bundled, configured, or
system-provided MediaInfo CLI candidates.

| RID | Bundled native asset | Source |
| --- | --- | --- |
| `win-x64` | `native/MediaInfo.dll` | Official MediaArea archive |
| `win-arm64` | `native/MediaInfo.dll` | Official MediaArea archive |
| `osx-x64` | `native/libmediainfo.dylib` | Official universal MediaArea archive |
| `osx-arm64` | `native/libmediainfo.dylib` | Official universal MediaArea archive |
| `linux-x64` | `native/libmediainfo.so` and `native/libzen.so.0` | `MediaInfo.Core.Native` 26.1.0, matching RenderKit Studio |
| `linux-arm64` | None | External native, host, or CLI fallback |

The exact source URLs, archive hashes, file hashes, dependencies, and
availability boundary are recorded in `manifest.json`. Reproduce or refresh
the binary drop with:

```powershell
pwsh ./build/Sync-RenderKitMediaInfoAssets.ps1
```

The sync script refuses archive or extracted-file hash mismatches. On Windows,
the official x64 and ARM64 DLLs are also Authenticode-signed by MediaArea.

The `licenses` folders preserve the upstream MediaInfoLib license. The Linux
x64 folder also contains the ZenLib license for its bundled dependency.
