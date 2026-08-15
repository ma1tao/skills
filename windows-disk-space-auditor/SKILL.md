---
name: windows-disk-space-auditor
description: Analyze Windows disk-space usage safely and generate a standalone visual HTML report plus machine-readable JSON. Use when a user says the C drive or another Windows drive is full, asks what is consuming storage, requests a rescan or before/after comparison, wants to know what can be deleted and how, or asks for a disk-usage HTML dashboard. Supports conservative cleanup classification and instructions; never treats an analysis request as permission to delete files.
---

# Windows Disk Space Auditor

Perform a read-only Windows storage audit, explain the results in plain language, and deliver a local HTML report. Keep actual drive usage separate from logical directory sizes because Windows hard links can cause duplicate counting.

## Audit workflow

1. Confirm the host is Windows and identify the requested drive. Default to `C` when the user says “system drive” or does not specify one.
2. Tell the user the scan is read-only and may take one to three minutes. Send a short progress update at least every 60 seconds while it runs.
3. Choose a writable output directory inside the current workspace unless the user specifies another location. Do not place reports in the scanned drive root.
4. Run the bundled scanner:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\analyze-windows-disk.ps1" -DriveLetter C -OutputDirectory "<absolute-output-dir>"
   ```

   Use `pwsh` instead of `powershell` when appropriate. Preserve quoted literal paths.
5. Inspect the printed `PROFILE_PATH`, `ISOLATED_PROFILE`, `UNREADABLE_ITEMS`, and `ADMINISTRATOR` values. If `ISOLATED_PROFILE=1`, do not present the user-folder totals as real; rerun outside the file sandbox with approval. Pass `-UserProfilePath "C:\Users\<actual-user>"` when the environment still resolves an isolation profile. If protected folders remain inaccessible, distinguish ordinary sandbox escape from a true UAC administrator token and label directory totals as lower bounds. Do not block the report when physical drive totals are available.
6. Capture the `HTML_REPORT` and `JSON_REPORT` paths printed by the script. Read the JSON report for the answer; do not scrape the HTML.
7. Summarize:
   - total, used, free, and free percentage;
   - the largest main storage areas;
   - the largest current-user and AppData folders;
   - usually safe cleanup candidates;
   - items requiring review;
   - protected system areas that must not be deleted manually.
8. Link the standalone HTML report using its absolute local path. State that it is local and sends no data to the network.

## Interpret results correctly

- Treat `drive.used_bytes` and `drive.free_bytes` as authoritative for total physical usage.
- Treat directory rows as logical visible sizes. Never add Windows, WinSxS, System32, user, and program rows together and present the result as physical usage.
- Explain that WinSxS and System32 share hard-linked files when their apparent totals look disproportionate.
- Treat non-elevated or error-bearing results as lower bounds. Surface `scan.warnings`.
- Rank by bytes, but use rounded GB only for presentation.
- Do not infer that a large folder is disposable merely because it is a cache-like location.

## Give cleanup guidance

Read [references/cleanup-safety.md](references/cleanup-safety.md) whenever the user asks what can be deleted, how to delete it, or asks the agent to perform cleanup.

Use three labels:

- **Usually safe after review:** Recycle Bin, temporary files through Windows Storage, application-provided cache cleanup, old crash diagnostics.
- **Review first:** Downloads, SDKs, emulator images, package caches, IDE data, cloud-sync copies, and application folders under AppData.
- **Never delete manually:** WinSxS, System32, SysWOW64, Windows Installer, Program Files contents, pagefile, hiberfil, recovery and boot data.

Prefer exact GUI steps or the owning application's uninstaller. Describe the consequence, such as redownloading dependencies or losing local sessions.

## Handle cleanup requests safely

An audit request is read-only. Do not delete anything unless the user explicitly asks for cleanup.

For an explicit cleanup request:

1. Inspect and resolve exact target paths.
2. Exclude protected paths and active workspace/project files.
3. State each target, size, expected effect, and recoverability.
4. Close related applications or ask the user to close them.
5. Obtain required confirmation/approval before permanent or administrator-level changes.
6. Prefer supported application/Windows cleanup and recoverable deletion.
7. Rerun the audit after cleanup and compare free space with the previous report.

Never issue recursive deletion against a drive root, profile root, unresolved variable, wildcard-expanded unknown set, or computed path that has not been validated.

## Rescans and comparisons

When the user asks to scan again, run the scanner again rather than reusing old measurements. If an earlier JSON report is available, compare:

- free-space change;
- folders that disappeared or shrank;
- folders that grew materially;
- remaining cleanup candidates.

Do not overwrite previous reports; the scanner timestamps every output.

## Report deliverables

The scanner creates:

- a standalone responsive HTML dashboard from `assets/report-template.html`;
- a JSON report containing raw bytes, rounded GB values, rankings, warnings, and cleanup candidates.

Keep both files together. The HTML is for the user; the JSON is the evidence source for the agent.

## Failure handling

- If PowerShell execution policy blocks the script, invoke it with `-ExecutionPolicy Bypass` for that process only.
- If the output directory is unwritable, switch to a writable workspace folder.
- If the scan is interrupted, report that totals are incomplete and rerun; do not present partial data as final.
- If HTML generation fails but JSON succeeds, summarize from JSON, fix the template/path issue, and regenerate the report.
- If the host is not Windows, state that the bundled scanner is Windows-only and use an appropriate read-only native alternative without pretending this script supports it.
