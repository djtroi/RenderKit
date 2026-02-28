# Import-Media Drive Detection Engine - Comprehensive Test Checklist

## Document Metadata
- Branch under test: `Import-Media-Drive-Detection-Engine`
- Feature scope:
  - Drive detection (`Get-RenderKitDriveCandidate`, `Select-RenderKitDriveCandidate`)
  - Interactive import wizard (`Import-Media` with no params)
  - Scan/filter/select/classify/transfer flow
  - Simulation-to-real transfer follow-up
  - Revision log output format and readability
- Test type: Manual functional, negative, robustness, security, and regression
- Target OS: Windows 10/11
- Target shell: PowerShell 5.1+ and PowerShell 7+

## General Test Rules
- [ ] Use a dedicated test machine or isolated test folders.
- [ ] Never test against real production footage.
- [ ] Record command, timestamp, result, and screenshot for each failed case.
- [ ] Always reset/clean test data after destructive transfer scenarios.
- [ ] Run both interactive and non-interactive test paths.

## Test Environment Setup

### Prerequisites
- [ ] RenderKit module code available locally.
- [ ] At least one valid RenderKit project exists.
- [ ] `%APPDATA%\RenderKit\Devices.json` is readable/writable.
- [ ] One source location with mixed file types and nested folders exists.
- [ ] (Optional but recommended) One removable source and one fixed drive source.

### Suggested Test Data (PowerShell)
Run once to create deterministic test data:

```powershell
$root = "C:\RK_TestData"
$srcA = Join-Path $root "SourceA"
$srcB = Join-Path $root "SourceB_Ambiguous"
$projRoot = "C:\RK_Projects"
$projName = "RK_IMPORT_TEST_001"

New-Item -ItemType Directory -Path $srcA,$srcB,$projRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $srcA "DCIM\100TEST"),(Join-Path $srcA "AUDIO"),(Join-Path $srcA "DOCS") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $srcB "MIXED") -Force | Out-Null

"video-a" | Set-Content (Join-Path $srcA "DCIM\100TEST\clip001.mp4")
"video-b" | Set-Content (Join-Path $srcA "DCIM\100TEST\clip002.mov")
"audio-a" | Set-Content (Join-Path $srcA "AUDIO\take001.wav")
"audio-b" | Set-Content (Join-Path $srcA "AUDIO\take002.mp3")
"image-a" | Set-Content (Join-Path $srcA "DCIM\100TEST\frame001.jpg")
"doc-a"   | Set-Content (Join-Path $srcA "DOCS\notes.txt")
"archive" | Set-Content (Join-Path $srcA "DOCS\pack.zip")
"unknown" | Set-Content (Join-Path $srcA "DOCS\mystery.xyz")

# Ambiguous candidates (example extension used by multiple mappings in your config)
"amb-1" | Set-Content (Join-Path $srcB "MIXED\ambiguous001.mp4")
"amb-2" | Set-Content (Join-Path $srcB "MIXED\ambiguous002.mp4")

Import-Module "k:\Programming\RenderKit\src\RenderKit.psd1" -Force
Set-ProjectRoot -Path $projRoot
New-Project -Name $projName -Template "default"
```

## Smoke Test (Fast Go/No-Go)
- [ ] Module import works.
- [ ] `Get-RenderKitDriveCandidate` runs without unhandled exception.
- [ ] `Import-Media` starts wizard when called without parameters.
- [ ] Wizard reaches file preview.
- [ ] Classification preview appears.
- [ ] Transfer simulation works.
- [ ] Simulation follow-up asks whether real transfer should run.
- [ ] Revision log file is written and readable text format (not JSON blob).

Command sample:
```powershell
Import-Module "k:\Programming\RenderKit\src\RenderKit.psd1" -Force
Import-Media
```

---

## Detailed Test Cases

## A. Module Loading and Baseline Configuration

### TC-A-001 Module import
- [ ] Objective: Ensure module loads cleanly.
- [ ] Steps:
  1. Run:
     ```powershell
     Import-Module "k:\Programming\RenderKit\src\RenderKit.psd1" -Force -Verbose
     ```
  2. Check exported commands.
- [ ] Expected:
  - No parse/runtime import errors.
  - `Import-Media`, `Get-RenderKitDriveCandidate`, `Select-RenderKitDriveCandidate` available.

### TC-A-002 Project root config available
- [ ] Steps:
  1. Run:
     ```powershell
     Set-ProjectRoot -Path "C:\RK_Projects"
     ```
  2. Verify `%APPDATA%\RenderKit\config.json`.
- [ ] Expected:
  - `DefaultProjectPath` exists and points to configured path.

## B. Drive Detection Engine

### TC-B-001 Candidate list default behavior
- [ ] Steps:
  1. Run:
     ```powershell
     Get-RenderKitDriveCandidate
     ```
- [ ] Expected:
  - Returns candidates for removable + supported filesystems by default.
  - No unhandled exception.

### TC-B-002 No candidates fallback prompt
- [ ] Preconditions: environment where default query returns no candidates.
- [ ] Steps:
  1. Run:
     ```powershell
     Get-RenderKitDriveCandidate
     ```
  2. At prompt `Include fixed drives? [Y/N]` answer `N`.
- [ ] Expected:
  - Graceful exit.
  - No crash.

### TC-B-003 No candidates -> include fixed -> selection flow
- [ ] Steps:
  1. Run `Get-RenderKitDriveCandidate`.
  2. Answer `Y` to include fixed drives.
- [ ] Expected:
  - Selection flow opens.
  - Candidate table displayed with index, drive, volume, filesystem, serial, whitelist, score.

### TC-B-004 Selection action menu
- [ ] Steps:
  1. Run:
     ```powershell
     Select-RenderKitDriveCandidate -IncludeFixed
     ```
  2. Verify action prompt `[S]/[W]/[C]`.
- [ ] Expected:
  - Prompt text clear and deterministic.
  - Unknown action shows warning and re-prompts.

### TC-B-005 Select valid index
- [ ] Steps:
  1. Choose action `S`.
  2. Enter valid index.
- [ ] Expected:
  - Returns selected drive object.

### TC-B-006 Select invalid index handling
- [ ] Steps:
  1. Choose action `S`.
  2. Enter non-numeric input.
  3. Enter out-of-range index.
- [ ] Expected:
  - Friendly warning.
  - Re-prompt until valid/cancel.

### TC-B-007 Whitelist selected drive
- [ ] Steps:
  1. Choose action `W`.
  2. Enter valid index.
  3. Confirm selection prompt (`Use drive as source now?`).
  4. Check:
     ```powershell
     Get-RenderKitDeviceWhitelist
     ```
- [ ] Expected:
  - Drive volume/serial appended to whitelist.
  - No duplicate explosion on repeated write.

### TC-B-008 Cancel flow
- [ ] Steps:
  1. Choose action `C`.
- [ ] Expected:
  - Returns `$null` cleanly.

### TC-B-009 Include unsupported filesystem
- [ ] Steps:
  1. Run:
     ```powershell
     Get-RenderKitDriveCandidate -IncludeFixed -IncludeUnsupportedFileSystem
     ```
- [ ] Expected:
  - Unsupported FS candidates appear with low/zero FS priority.

## C. Import Wizard - Navigation and UX Clarity

### TC-C-001 Wizard starts with no params
- [ ] Steps:
  1. Run:
     ```powershell
     Import-Media
     ```
- [ ] Expected:
  - Wizard starts and announces steps.
  - No immediate raw parameter dump.

### TC-C-002 Step 1 project selection table
- [ ] Steps:
  1. In wizard Step 1, inspect table.
  2. Select project by index.
- [ ] Expected:
  - Table includes project name, template, path.
  - Invalid index handling works.

### TC-C-003 Step 1 project selection by path
- [ ] Steps:
  1. Provide absolute project root path directly.
- [ ] Expected:
  - Path is validated (`.renderkit\project.json` present).
  - Invalid path gets clear warning and re-prompt.

### TC-C-004 Step 2 source selection with context table
- [ ] Steps:
  1. Continue to source selection.
  2. Verify displayed context/status table.
- [ ] Expected:
  - Current step, selected project, source mode context visible.

### TC-C-005 Source subfolder selection
- [ ] Steps:
  1. Choose source drive.
  2. Enter subfolder (relative and absolute variants).
- [ ] Expected:
  - Resolved path validated and accepted if existing.
  - Non-existing path rejected with re-prompt.

### TC-C-006 Manual source fallback
- [ ] Steps:
  1. Choose `Q` to manual source path input.
  2. Provide valid/invalid paths.
- [ ] Expected:
  - Same validation behavior as above.

### TC-C-007 Step 3 config table clarity
- [ ] Steps:
  1. Reach scan configuration step.
  2. Verify summary table before scan.
- [ ] Expected:
  - Chosen options are visible and understandable.

## D. Scan and Filter

### TC-D-001 Full scan no filters
- [ ] Steps:
  1. Use `SourceA`.
  2. Skip optional filters.
- [ ] Expected:
  - `Phase 2 preview` appears.
  - File count equals source content.

### TC-D-002 Folder filter
- [ ] Steps:
  1. Enable interactive filters.
  2. Filter folder to `DCIM` only.
- [ ] Expected:
  - Only files under matching folders remain.

### TC-D-003 Date range filter
- [ ] Steps:
  1. Set `FromDate` and `ToDate` boundaries.
- [ ] Expected:
  - Files outside date window excluded.

### TC-D-004 Wildcard filter
- [ ] Steps:
  1. Use wildcard `*.mp4,*.wav`.
- [ ] Expected:
  - Only matching names/paths selected.

### TC-D-005 Invalid date handling
- [ ] Steps:
  1. Enter invalid date string.
- [ ] Expected:
  - Clear warning and retry prompt.

## E. File Selection and Safety Confirmation

### TC-E-001 Auto-select all
- [ ] Steps:
  1. Choose auto-select all.
- [ ] Expected:
  - Selection contains all matched files.

### TC-E-002 Manual selection by indices/ranges
- [ ] Steps:
  1. Manual mode.
  2. Provide `0,2,5-8`.
- [ ] Expected:
  - Correct subset selected.
  - Invalid tokens rejected with clear error.

### TC-E-003 Selection checkpoint review loop
- [ ] Steps:
  1. Reach selection checkpoint.
  2. Choose `E` and modify selection.
  3. Choose `Y`.
- [ ] Expected:
  - Updated selection preview shown.
  - Loop exits only on explicit continue/cancel.

### TC-E-004 Selection cancel
- [ ] Steps:
  1. In selection checkpoint choose `C`.
- [ ] Expected:
  - Import is cancelled safely.
  - No transfer attempt.

### TC-E-005 Confirm import prompt
- [ ] Steps:
  1. Proceed with selected files.
  2. Verify confirmation dialog with file count + size.
- [ ] Expected:
  - Correct aggregate values displayed.

## F. Classification, Mapping, and Unassigned Handling

### TC-F-001 Standard mapping assignment
- [ ] Steps:
  1. Use source with known types (`mp4`, `wav`, `jpg`, `txt`).
  2. Run classification.
- [ ] Expected:
  - Files assigned into mapped template destinations.

### TC-F-002 Ambiguous extension case shows filenames
- [ ] Preconditions: Extension exists in more than one folder mapping path.
- [ ] Steps:
  1. Trigger ambiguous extension case (e.g., `.mp4` duplicates).
  2. Observe prompt content.
- [ ] Expected:
  - UI shows filename(s), folder, and size; not extension only.

### TC-F-003 Unassigned Prompt mode
- [ ] Steps:
  1. Set unassigned handling to `Prompt`.
  2. Include unknown extension (`.xyz`).
- [ ] Expected:
  - Destination folder table displayed.
  - Per-extension decision requested.

### TC-F-004 Unassigned ToSort mode
- [ ] Steps:
  1. Set unassigned handling to `ToSort`.
- [ ] Expected:
  - Unassigned files routed to `TO SORT`.

### TC-F-005 Unassigned Skip mode
- [ ] Steps:
  1. Set unassigned handling to `Skip`.
- [ ] Expected:
  - Files marked skipped, excluded from transfer.

### TC-F-006 Regression check: AutoConfirm no forced ToSort
- [ ] Steps:
  1. Enable auto-confirm.
  2. Keep unassigned handling on `Prompt`.
- [ ] Expected:
  - System still asks/handles unassigned according to configured mode.
  - No silent forced `ToSort`.

## G. Transfer Engine (Simulate and Real)

### TC-G-001 Transfer mode prompt appears at end
- [ ] Steps:
  1. Run full wizard.
  2. Verify transfer mode prompt appears after classification.
- [ ] Expected:
  - Prompt order is correct (transfer decision is final).

### TC-G-002 Simulate transfer
- [ ] Steps:
  1. Choose transfer mode `Simulate`.
- [ ] Expected:
  - No source deletion.
  - No final moved files from temp to destinations.
  - Status includes simulated transactions.

### TC-G-003 Simulation -> real follow-up question
- [ ] Steps:
  1. Complete simulation.
  2. Verify prompt: execute real transfer now?
- [ ] Expected:
  - Prompt appears every time for wizard simulation runs (except explicit `-WhatIf` mode).

### TC-G-004 Simulation -> real YES
- [ ] Steps:
  1. Answer `Yes` to post-simulation real transfer.
- [ ] Expected:
  - Real transfer executes.
  - Files physically copied/moved to project targets.

### TC-G-005 Simulation -> real NO
- [ ] Steps:
  1. Answer `No` after simulation.
- [ ] Expected:
  - Real transfer does not run.
  - Final state remains simulation-only.

### TC-G-006 Real transfer direct mode
- [ ] Steps:
  1. Select `Real` transfer mode.
- [ ] Expected:
  - Temp staging path created under `.renderkit\import-temp`.
  - Hash verification passes before move.
  - Progress reporting updates.

### TC-G-007 Hash mismatch safety
- [ ] Steps:
  1. Inject fault (modify source during transfer in controlled lab scenario).
- [ ] Expected:
  - File marked failed.
  - No corrupted final destination write.
  - Error logged.

### TC-G-008 Duplicate filename conflict handling
- [ ] Steps:
  1. Place two files with same name targeting same destination.
- [ ] Expected:
  - Unique suffix naming (`_001`, `_002`, etc.) applied.
  - No overwrite unless explicitly intended.

### TC-G-009 Empty transfer candidate set
- [ ] Steps:
  1. Select only skipped/unassigned-no-destination files.
- [ ] Expected:
  - Transfer returns zero planned files gracefully.

## H. Revision Log and Reporting

### TC-H-001 Final report visibility
- [ ] Steps:
  1. Complete import flow.
- [ ] Expected:
  - Final report table prints source, imported files, size, duration, speed, unassigned counts.

### TC-H-002 Revision log created
- [ ] Steps:
  1. Run successful import with valid project root.
  2. Verify `.renderkit\import-*.log`.
- [ ] Expected:
  - Log file exists.

### TC-H-003 Revision log readability format
- [ ] Steps:
  1. Open log file.
- [ ] Expected:
  - Human-readable text/list format.
  - Contains sections:
    - `[Context]`
    - `[Filters]`
    - `[Counts]`
    - `[Bytes]`
    - `[Transfer]`
    - `[Transactions]`

### TC-H-004 Revision log content integrity
- [ ] Steps:
  1. Compare log values to final report and runtime output.
- [ ] Expected:
  - Counts, bytes, mode (`SimulationMode`) and source path consistent.

## I. Robustness and Failure Handling

### TC-I-001 Invalid source path
- [ ] Steps:
  1. Provide non-existent source path.
- [ ] Expected:
  - Clear error.
  - No partial transfer.

### TC-I-002 Invalid project root
- [ ] Steps:
  1. Provide path without `.renderkit\project.json`.
- [ ] Expected:
  - Validation error.
  - Import stops safely.

### TC-I-003 Permission denied destination
- [ ] Steps:
  1. Use project destination with restricted ACL.
- [ ] Expected:
  - Transfer failures logged per file.
  - Process continues for other files where possible.

### TC-I-004 Source disconnect mid-run
- [ ] Steps:
  1. During transfer, disconnect external source.
- [ ] Expected:
  - Affected files fail cleanly.
  - No unhandled crash.

### TC-I-005 Very long paths
- [ ] Steps:
  1. Test deep nested source paths near path length limits.
- [ ] Expected:
  - Either handled or clearly reported with actionable error.

### TC-I-006 Special characters in filenames
- [ ] Steps:
  1. Include spaces, unicode, brackets, semicolons, quotes.
- [ ] Expected:
  - Proper transfer and logging, no injection or parse breakage.

## J. Security-Focused Tests

### TC-J-001 Path traversal defense
- [ ] Steps:
  1. Attempt source subpath entries like `..\..\Windows`.
- [ ] Expected:
  - Resolved path validation prevents unintended traversal outside intended source context.

### TC-J-002 Script injection via input text
- [ ] Steps:
  1. Enter malicious strings in prompts (e.g. `$(Remove-Item C:\ -Recurse)`).
- [ ] Expected:
  - Treated as plain text input.
  - No command execution side effects.

### TC-J-003 Whitelist abuse resilience
- [ ] Steps:
  1. Repeatedly add same drive to whitelist.
- [ ] Expected:
  - No uncontrolled growth from duplicates.

### TC-J-004 Log data leakage review
- [ ] Steps:
  1. Inspect revision logs for sensitive data beyond expected fields.
- [ ] Expected:
  - No secrets/tokens/passwords logged.

### TC-J-005 Symlink/junction behavior
- [ ] Steps:
  1. Add symlinked directories in source.
- [ ] Expected:
  - No infinite recursion.
  - Behavior documented and stable.

## K. Performance and Scale

### TC-K-001 Medium dataset performance
- [ ] Steps:
  1. Test 5k-20k files with mixed types.
- [ ] Expected:
  - Acceptable scan time.
  - Stable memory usage.

### TC-K-002 Large file transfer
- [ ] Steps:
  1. Include 20GB+ sample file.
- [ ] Expected:
  - Stable progress updates.
  - Correct final hash validation.

### TC-K-003 Many small files
- [ ] Steps:
  1. Include 50k tiny files.
- [ ] Expected:
  - No severe slowdown from excessive per-file overhead.

## L. Regression Tests (Backward Compatibility)

### TC-L-001 Non-interactive scan flow
- [ ] Steps:
  1. Run:
     ```powershell
     Import-Media -ScanAndFilter -SourcePath "C:\RK_TestData\SourceA" -AutoSelectAll -AutoConfirm
     ```
- [ ] Expected:
  - Works as before.
  - No wizard launch.

### TC-L-002 Parameterized transfer flow
- [ ] Steps:
  1. Run explicit classify/transfer flags:
     ```powershell
     Import-Media -ScanAndFilter -SourcePath "C:\RK_TestData\SourceA" -ProjectRoot "C:\RK_Projects\RK_IMPORT_TEST_001" -Classify -Transfer -AutoSelectAll -AutoConfirm -UnassignedHandling ToSort
     ```
- [ ] Expected:
  - Full pipeline runs with parameters.

### TC-L-003 Drive candidate command behavior unchanged for explicit switches
- [ ] Steps:
  1. Run:
     ```powershell
     Get-RenderKitDriveCandidate -IncludeFixed -IncludeUnsupportedFileSystem
     ```
- [ ] Expected:
  - Returns expected object list without forced interactive prompt.

---

## Pass/Fail Exit Criteria
- [ ] All critical flows pass:
  - Drive detection
  - Wizard navigation
  - Classification correctness
  - Transfer safety
  - Revision logging
- [ ] No data-loss defects.
- [ ] No unhandled exceptions in interactive mode.
- [ ] Security tests reveal no command injection/path traversal vulnerability.
- [ ] Performance is acceptable for target workload.

## Test Run Log Template
Use this section for each execution:

- [ ]  Test Run ID:
- [ ] Date/Time:
- [ ] Tester:
- [ ] Machine/OS:
- [ ] PowerShell version:
- [ ] Module version/commit:
- [ ] Scenario subset executed:
- [ ] Result summary:
- [ ] Defects opened (IDs):
- [ ] Notes:
