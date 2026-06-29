# MediaInfo Bundle Layout

RenderKit ships MediaInfo per runtime identifier (RID). The resolver should use
the current RID first, then explicit environment overrides, and only then any
system installation.

Expected layout:

```text
src/Resources/ThirdParty/MediaInfo/
  manifest.json
  win-x64/
    bin/mediainfo.exe
    native/MediaInfo.dll
    licenses/
  win-arm64/
    bin/mediainfo.exe
    native/MediaInfo.dll
    licenses/
  osx-x64/
    bin/mediainfo
    native/libmediainfo.dylib
    licenses/
  osx-arm64/
    bin/mediainfo
    native/libmediainfo.dylib
    licenses/
  linux-x64/
    bin/mediainfo
    native/libmediainfo.so
    licenses/
  linux-arm64/
    bin/mediainfo
    native/libmediainfo.so
    licenses/
```

The `licenses` folder must preserve license files shipped with the upstream
MediaInfo binary package for that RID.
