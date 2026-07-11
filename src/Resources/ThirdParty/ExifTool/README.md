# Bundled ExifTool runtime

RenderKit bundles ExifTool 13.59 from the official ExifTool distributions.
Version 13.59 was selected because upstream identifies it as the security
update published on 2026-05-27.

ExifTool is an application written in Perl, not a native shared-library API.
The primary integration is therefore the bundled command-line program:

- Windows x86 and x64 use the corresponding upstream Windows executable,
  including its adjacent `exiftool_files` runtime directory.
- macOS and Linux use the `exiftool` program and `lib` directory from the
  official full distribution. A Perl interpreter is required.
- Windows ARM64 has no upstream native executable in this release and uses
  configured host or system-CLI resolution.

Resolution order is:

1. `RENDERKIT_EXIFTOOL_PATH`
2. the bundled runtime for the current process RID
3. `RENDERKIT_EXIFTOOL_HOST`
4. `exiftool` / `exiftool.exe` on `PATH`

`RENDERKIT_EXIFTOOL_PERL` may select the Perl interpreter used by the bundled
portable program. The metadata-host contract is:

```text
<host> exiftool run -- <ExifTool arguments>
```

`manifest.json` records upstream archive URLs and checksums. `files.sha256`
records every redistributed payload and license file. The full ExifTool
license notice is in `licenses/ExifTool-README.txt`; the Perl Artistic and GPL
terms are extracted to `licenses/Perl-Artistic.txt` and
`licenses/Perl-Copying.txt`. Upstream Strawberry Perl and dependency license
material also remains inside each Windows `exiftool_files` directory.
