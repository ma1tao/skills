# Windows Disk Cleanup Safety

Use this reference when explaining cleanup choices or when a user asks to remove files. Prefer supported application and Windows cleanup flows over raw filesystem deletion.

Never run `takeown`, change ACLs, force-unlock files, stop Windows services, or bypass access-denied errors merely to reclaim space. Do not follow junctions, symbolic links, or other reparse points outside the measured root. Cloud placeholders, sparse files, VHDX files, and hard links can have apparent sizes that differ from reclaimable physical space.

## Safety levels

### Usually safe after review

| Area | Preferred method | Guardrail |
|---|---|---|
| Recycle Bin | Open Recycle Bin, review, then empty it | Confirm no deleted file is still needed |
| User temporary files | Settings > System > Storage > Temporary files | Close applications; skip files reported as in use |
| Windows Update cleanup | Settings > System > Storage > Temporary files > Windows Update Cleanup | Never manually delete `WinSxS` or servicing folders |
| Crash dumps and application logs | Use the application's cleanup option or remove old diagnostic files | Keep them when investigating a crash or support case |
| Browser/application caches | Use the application's storage or cache settings | Expect the cache to be rebuilt |

Microsoft recommends Storage settings, Cleanup recommendations, Storage Sense, and Disk Cleanup as supported cleanup paths:

- https://support.microsoft.com/en-US/Windows/Experience/Storage-FileManagement/free-up-drive-space-in-windows
- https://support.microsoft.com/en-us/windows/experience/storage-filemanagement/storage-settings-in-windows

### Review first

| Area | Why it may be large | Safe approach |
|---|---|---|
| Downloads, Desktop, Documents, media | User-created files | List the largest files; move or delete only selected items |
| `.cache` | Shared tool and model caches | Identify the owning tool; expect downloads after cleanup |
| `.gradle`, `.npm`, `.pnpm-store`, `.cargo`, `.rustup` | Build dependencies and toolchains | Use the package manager's cleanup/uninstall flow; close IDEs first |
| Playwright/browser binaries | Test browser installations | Remove only versions not required by active projects |
| IDE extension caches | Cached installers and extensions | Prefer the IDE's extension manager; preserve settings and project data |
| AppData application folders | Settings, sessions, local databases, attachments, caches | Drill down one level; delete only named cache/log folders or uninstall an unused app |
| SDKs and emulator images | Development system images and toolchains | Use the SDK manager or product uninstaller; removing them may require redownload |
| Cloud-sync local copies | Offline copies of cloud files | Use Files On-Demand or the provider's "free up space" command |
| WSL, Docker, virtual machines | Virtual disks may contain unique data and do not always shrink after guest deletion | Inventory and back up first; use the product's supported cleanup and compaction flow |

Before deleting an entire application-data folder:

1. Confirm the application is uninstalled or definitely unused.
2. Close all related processes.
3. Preserve folders named `User`, `Profiles`, `Local Storage`, `IndexedDB`, `databases`, `projects`, or `workspaces` unless the user explicitly accepts losing local state.
4. Prefer renaming to `.old` for a short verification window when enough free space exists.
5. Reopen the retained application and verify settings and projects before permanent deletion.

### Never delete manually

- `C:\Windows\WinSxS`
- `C:\Windows\System32`
- `C:\Windows\SysWOW64`
- `C:\Windows\Installer`
- `C:\Program Files` and `C:\Program Files (x86)` application folders
- `pagefile.sys`, `swapfile.sys`, and `hiberfil.sys`
- `System Volume Information`, boot files, recovery partitions, and EFI partitions
- Unknown files owned by Windows servicing, Defender, drivers, or an installer
- `C:\ProgramData\Package Cache`, `WindowsApps`, driver-store contents, MSI/MSP caches, and Visual Studio installer caches
- WSL `ext4.vhdx`, Docker data disks and volumes, Hyper-V/VMware disks and snapshots
- Credential, certificate, wallet, password-manager, token, DPAPI, EFS, or Windows Hello data

WinSxS contains hard-linked component-store files. A normal recursive scan can count the same physical file multiple times. Microsoft warns that manually deleting WinSxS can prevent Windows from booting or updating. Use supported component cleanup only:

- Analyze: `DISM.exe /Online /Cleanup-Image /AnalyzeComponentStore`
- Supported cleanup: `DISM.exe /Online /Cleanup-Image /StartComponentCleanup`
- Official guidance: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder?view=windows-11

Do not recommend `/ResetBase` as routine cleanup. It removes the ability to uninstall existing update packages and requires an explicit explanation and confirmation.

## AppData classification

Treat AppData as application state, not as a cache root. `Roaming`, `Local`, and Store-app `Packages` can contain databases, mail, browser profiles, sessions, sync queues, game saves, credentials, and local documents.

Classify an AppData subfolder as usually safe only when all of these are true:

1. Identify the owning application.
2. The application UI or official documentation describes the exact subfolder as disposable cache/log data.
3. It does not contain profiles, databases, sessions, credentials, recovery state, or pending sync data.
4. The application is fully closed.
5. Explain the rebuild or redownload consequence.

Otherwise classify it as review-first. Never suggest deleting an entire AppData, `Packages`, `LocalState`, `User`, `Profiles`, `Workspaces`, `IndexedDB`, or database root as generic cleanup.

## High-risk commands

Do not recommend these as routine cleanup. They require a specific user request, preview/inventory, backup where applicable, and separate confirmation:

```text
DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
wsl --unregister <Distro>
docker system prune --volumes
docker volume prune
conda clean --force-pkgs-dirs
git clean -fdx
git gc --prune=now
```

`/ResetBase` removes update rollback options, WSL unregister deletes a distribution, Docker volumes may contain databases, and Git/Conda commands can destroy unique or difficult-to-rebuild data.

## Deletion authorization workflow

Analysis requests authorize read-only inspection only. They do not authorize cleanup.

When a user explicitly asks for cleanup:

1. Resolve every target to an absolute path.
2. Report the exact paths, measured size, expected consequence, and recovery method.
3. Exclude protected paths and current project/workspace files.
4. Close or ask the user to close owning applications.
5. Request confirmation before permanent deletion or any operation requiring administrator privileges.
6. Prefer app uninstallers, Windows Storage settings, or recoverable deletion.
7. Never use broad globs, unresolved environment variables, the drive root, the user-profile root, or recursive deletion against a computed unchecked path.
8. After cleanup, rerun the scanner and report the before/after free space.

## Developer-cache methods

Prefer an owning tool's inventory and cleanup command; never delete the whole tool home blindly.

| Tool | Inspect or clean conservatively | Important boundary |
|---|---|---|
| npm | `npm cache verify` | Forced cache purge causes redownloads and is rarely the first step |
| pip | `py -m pip cache info`, then `py -m pip cache purge` after confirmation | `.venv` is an environment, not cache |
| pnpm | `pnpm store path`, then `pnpm store prune` | Do not manually delete the content-addressed store |
| NuGet | `dotnet nuget locals all --list`; clean only confirmed cache types | Global packages require project restore afterward |
| Conda | `conda clean --all --dry-run` before any cleanup | Do not force-remove package directories used by environments |
| Gradle | Let Gradle's retention policy work or target only known caches | `.gradle` can also contain properties, wrappers and JDK data |
| Cargo | Use `cargo clean --dry-run --verbose` in a confirmed project | Do not remove `.cargo` configuration, credentials or binaries |
| Docker | Start with `docker system df`; inventory images, containers and volumes | Never include volumes in a generic cleanup action |
| WSL | Clean package caches inside the distribution; export a backup before advanced operations | `wsl --unregister` permanently deletes the distribution |

## Reporting language

- Separate **measured logical folder size** from **actual drive usage**.
- Label uncertain or inaccessible totals explicitly.
- Do not promise that every cache can be deleted safely.
- Give a conservative reclaim estimate rather than summing overlapping folders.
- Explain what will be redownloaded, reset, or lost.
