# Cross-Platform User Storage

RenderKit keeps user-owned files outside the installed module directory. The
private storage service separates files by purpose so configuration, durable
state, cache data, and user-created resources can evolve independently.

## Storage kinds

| Kind | Contents |
| --- | --- |
| Configuration | RenderKit settings such as the default project root |
| State | Device whitelist, project registry, and future job/outbox state |
| Cache | Reconstructable cached data |
| User data | User-created templates and mappings |

## Default locations

### Windows

```text
Configuration: %APPDATA%\RenderKit
State:         %LOCALAPPDATA%\RenderKit
Cache:         %LOCALAPPDATA%\RenderKit\cache
User data:     %APPDATA%\RenderKit
```

### Linux

RenderKit follows the XDG Base Directory environment variables when they are
set and uses their standard home-directory fallbacks otherwise.

```text
Configuration: ${XDG_CONFIG_HOME:-$HOME/.config}/renderkit
State:         ${XDG_STATE_HOME:-$HOME/.local/state}/renderkit
Cache:         ${XDG_CACHE_HOME:-$HOME/.cache}/renderkit
User data:     ${XDG_DATA_HOME:-$HOME/.local/share}/renderkit
```

### macOS

Explicit XDG variables are respected. Without them, RenderKit uses native
macOS application directories.

```text
Configuration: $HOME/Library/Application Support/RenderKit
State:         $HOME/Library/Application Support/RenderKit
Cache:         $HOME/Library/Caches/RenderKit
User data:     $HOME/Library/Application Support/RenderKit
```

## Portable and test override

Set `RENDERKIT_HOME` to isolate all RenderKit user storage below one directory:

```text
RENDERKIT_HOME/
  config/
  state/
  cache/
  data/
```

This override is intended for automated tests, CI, sandboxes, and explicitly
portable installations. It takes precedence over native and XDG locations.

## Legacy data

RenderKit preserves existing user data when the semantic location changes.
Legacy configuration, device whitelist, template, and mapping files are copied
to their new location only when the destination does not already exist.
Existing destination data is never overwritten by automatic migration.

## JSON persistence

RenderKit-owned JSON state is written through a shared persistence service:

1. an exclusive sidecar file lock is acquired with a bounded timeout;
2. the new JSON is written as UTF-8 without a byte-order mark to a temporary
   file in the destination directory;
3. the temporary file is parsed and optionally validated;
4. the previous valid destination is retained as `<name>.bak`;
5. the validated temporary file replaces the destination atomically where the
   file system supports replacement, with a backup-backed copy fallback;
6. temporary files and lock handles are released in `finally` blocks.

Operations that require read-modify-write consistency can use one lock for the
complete transaction so a writer reloads the latest value after acquiring the
lock. A persistent empty `<name>.lock` sidecar may remain on disk; ownership is
represented by the exclusive open file handle, not by the existence of the
sidecar.

The internal recovery operation restores a validated `.bak` file without
overwriting that backup with the corrupt or unwanted current file.

## Security

- User storage does not require administrator or root privileges.
- Paths are resolved by the storage service rather than assembled by public
  commands.
- The portable override is treated as an explicit user choice.
- Credentials and secrets must not be stored in these general-purpose JSON
  files.