# Changelog automation

RenderKit maintains `CHANGELOG.md` independently from the existing package and release workflows. The automation runs after pushes to `main` and semantic-version branches such as `1.1.3` or `1.2.0`.

## Required RS ticket

Pull requests targeting `main` or a semantic-version branch must normally include an RS ticket in their title:

```text
fix(backup): RS-1129 probe hardware encoders before backup
```

A pull request is exempt when its source branch consists only of one supported version:

```text
1.1.3
1.1.3-rc1
1.1.3-rc12
```

The exception is intentionally strict. Prefixes, paths, missing release-candidate numbers, and other suffixes remain ticket-required. These examples are not exempt:

```text
v1.1.3
release/1.1.3
1.1.3-rc
1.1.3-beta1
```

RenderKit uses squash merges for normal release-branch work. A normal change therefore retains its ticket in the resulting squash commit and becomes the single change represented in the changelog. A version-only squash commit such as `1.1.3 (#81)` is treated as release orchestration and is skipped by changelog processing.

Except for this version-only case, a pushed commit without an `RS-<number>` reference fails the changelog workflow and does not generate an entry.

## Dependabot and YouTrack

Dependabot is enabled only for the `github-actions` ecosystem. RenderKit's bundled native third-party tools are not managed by Dependabot because they are synchronized and verified through repository-specific asset logic rather than a supported package-manager manifest.

Dependabot pull requests receive their YouTrack ticket inside the `Maintain changelog` workflow:

```text
Dependabot YouTrack Ticket
  -> Require RS ticket
```

The prerequisite reads the current PR title, creates the YouTrack issue when no `RS-<number>` is present, and updates the title. `Require RS ticket` then reads the title again before validating it.

The Dependabot target branch is synchronized weekly. The highest stable semantic-version branch is selected when one exists; otherwise the configuration falls back to `main`.

Required repository configuration:

```text
Repository variable: YT_BASE_URL
Actions secret:       YT_API_TOKEN
Dependabot secret:    YT_API_TOKEN
```

The Dependabot secret is only required when Dependabot is enabled and must contain the same YouTrack token as the Actions secret.

Core does not set a Studio-specific `Edition` custom field when creating dependency tickets.

## Public repository runner boundary

RenderKit is public. Pull-request changelog and ticket validation therefore runs on GitHub-hosted runners rather than persistent self-hosted RenderKit runners.

This prevents untrusted fork pull requests from executing their checked-out code on privately managed runner hosts. The YouTrack close workflow additionally ignores PRs whose head repository is not the RenderKit repository.

## Changelog format

The updater follows Keep a Changelog semantics and maintains an `Unreleased` section with these categories:

- `Added`
- `Changed`
- `Deprecated`
- `Removed`
- `Fixed`
- `Security`

Conventional Commit prefixes determine the generated category:

| Prefix | Category |
| --- | --- |
| `feat:` | `Added` |
| `fix:` | `Fixed` |
| `security:` | `Security` |
| `remove:` | `Removed` |
| `deprecate:` | `Deprecated` |
| all other prefixes | `Changed` |

Each generated entry includes the ticket and the seven-character SHA of the squash commit:

```markdown
- **RS-1129:** Probed hardware encoders before automatic backup selection. (`a1b2c3d`)
```

The SHA is also used to prevent duplicate entries.

## OpenAI fallback

Commit subjects are used deterministically whenever they contain a useful description. OpenAI is called only when the remaining description is too short or generic.

The optional repository secret is:

```text
OPENAI_API_KEY
```

If the secret is missing, the API is unavailable, or the request fails, the updater uses the cleaned commit subject. Changelog maintenance therefore does not depend on OpenAI availability.

## Automated changelog commit

When `CHANGELOG.md` changes, GitHub Actions creates a commit similar to:

```text
chore(changelog): RS-1129 update Unreleased [skip changelog]
```

The `[skip changelog]` marker prevents an automation loop.

## Cutting a release

Development changes accumulate under `## [Unreleased]`. Before a semantic-version branch is merged into `main`, finalize the release in the version branch:

1. Set `RenderKit.psd1` `ModuleVersion` to the release version.
2. Move the accumulated Unreleased release notes under a dated heading, for example:

```markdown
## [1.1.3] - 2026-08-07
```

3. Leave a fresh empty `## [Unreleased]` block above the released version.
4. Ensure the release notes in `RenderKit.psd1` match the intended package release.
5. Merge the version branch into `main` only after the release PR checks pass.

The existing Core release workflow already accepts canonical bracketed headings such as `## [1.1.3] - YYYY-MM-DD` when extracting GitHub release notes.
