# Third-Party Notices

RenderKit itself is licensed under the MIT License. Some RenderKit builds or
distributions may include third-party components under their own licenses.

## MediaInfo / MediaInfoLib

RenderKit uses MediaInfo / MediaInfoLib for media file inspection and metadata
extraction.

- Project: https://mediaarea.net/MediaInfo
- License: BSD-style MediaInfo(Lib) license
- Copyright: Copyright (c) 2002-2026 MediaArea.net SARL. All rights reserved.

Binary redistribution notice required by MediaArea:

> This product uses MediaInfo library, Copyright (c) 2002-2026 MediaArea.net SARL.

MediaInfo(Lib) license text:

```text
Copyright (c) 2002-2026 MediaArea.net SARL. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this
list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

MediaInfo may rely on additional third-party libraries depending on platform
and build configuration. RenderKit distribution packaging must preserve the
license notices shipped with the MediaInfo binaries used for that package.

The Linux x64 bundle also redistributes ZenLib 0.4.41 under its zlib-style
license. Its complete license text is included beside the Linux runtime asset
at
`src/Resources/ThirdParty/MediaInfo/linux-x64/licenses/ZenLib-License.txt`.

Binary provenance, source archive/package URLs, and SHA-256 hashes are recorded
in `src/Resources/ThirdParty/MediaInfo/manifest.json`.

## ExifTool

RenderKit uses and may redistribute ExifTool for metadata inspection and
embedded metadata writes.

- Project: https://exiftool.org/
- Bundled version: 13.59
- Copyright: Copyright 2003-2026, Phil Harvey
- License: the same terms as Perl itself (Artistic License or GNU GPL)

The complete upstream ExifTool notice is included at
`src/Resources/ThirdParty/ExifTool/licenses/ExifTool-README.txt`. The Perl
Artistic and GPL terms are included beside it as `Perl-Artistic.txt` and
`Perl-Copying.txt`.

The official Windows ExifTool packages include a Strawberry Perl runtime and
its dependencies. Their complete license files and the upstream
`Licenses_Strawberry_Perl.zip` archive are preserved inside each
`src/Resources/ThirdParty/ExifTool/win-*/exiftool_files/` directory.

Source archive URLs, upstream SHA-256 values, runtime selection, and the
per-file payload hash manifest are recorded in
`src/Resources/ThirdParty/ExifTool/manifest.json` and
`src/Resources/ThirdParty/ExifTool/files.sha256`.
