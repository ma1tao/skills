#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]$')]
    [string]$DriveLetter = 'C',

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$UserProfilePath = '',

    [ValidateRange(5, 30)]
    [int]$Top = 12
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This scanner supports Windows only.'
}

$driveName = $DriveLetter.ToUpperInvariant()
$root = "$driveName`:\"
$drive = [System.IO.DriveInfo]::new($root)
if (-not $drive.IsReady) {
    throw "Drive $root is not ready."
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$warnings = New-Object System.Collections.Generic.List[string]
$skillRoot = Split-Path -Parent $PSScriptRoot
$stringsPath = Join-Path $skillRoot 'assets\strings.zh-CN.json'
if (-not (Test-Path -LiteralPath $stringsPath)) { throw "Localization file not found: $stringsPath" }
$strings = [System.IO.File]::ReadAllText($stringsPath) | ConvertFrom-Json

function Convert-ToGB([long]$Bytes) {
    return [math]::Round($Bytes / 1GB, 2)
}

function Encode-Html([object]$Value) {
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-GroupedTree {
    param(
        [string]$Path,
        [int]$GroupDepth = 1,
        [string]$Label = $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Label = $Label; Path = $Path; Exists = $false; Bytes = [long]0
            Files = 0; Errors = 0; Groups = @()
        }
    }

    Write-Host "Scanning: $Path"
    $prefix = $Path.TrimEnd('\') + '\'
    $bytes = [long]0
    $files = 0
    $map = @{}
    $scanErrors = @()

    Get-ChildItem -LiteralPath $Path -Force -File -Recurse -ErrorAction SilentlyContinue -ErrorVariable +scanErrors |
        ForEach-Object {
            $length = [long]$_.Length
            $bytes += $length
            $files++
            $relative = $_.FullName
            if ($relative.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $relative = $relative.Substring($prefix.Length)
            }
            $parts = @($relative -split '[\\/]')
            if ($parts.Count -le 1) {
                $key = '[files directly in root]'
            } else {
                $directoryParts = $parts[0..($parts.Count - 2)]
                $take = [math]::Min($GroupDepth, $directoryParts.Count)
                $key = ($directoryParts[0..($take - 1)] -join '\')
            }
            if (-not $map.ContainsKey($key)) { $map[$key] = [long]0 }
            $map[$key] = [long]$map[$key] + $length
        }

    $groups = @($map.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{ Name = $_.Key; Bytes = [long]$_.Value; GB = Convert-ToGB([long]$_.Value) }
    } | Sort-Object Bytes -Descending)

    if ($scanErrors.Count -gt 0) {
        $warnings.Add(($strings.warnings.unreadable -f $Label, $scanErrors.Count))
    }

    return [pscustomobject]@{
        Label = $Label; Path = $Path; Exists = $true; Bytes = $bytes
        Files = $files; Errors = $scanErrors.Count; Groups = $groups
    }
}

function Get-ProfileTree {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Path = $Path; Bytes = [long]0; Files = 0; Errors = 0; Groups = @(); AppDataGroups = @() }
    }

    Write-Host "Scanning profile: $Path"
    $prefix = $Path.TrimEnd('\') + '\'
    $bytes = [long]0
    $files = 0
    $groupMap = @{}
    $appMap = @{}
    $scanErrors = @()

    Get-ChildItem -LiteralPath $Path -Force -File -Recurse -ErrorAction SilentlyContinue -ErrorVariable +scanErrors |
        ForEach-Object {
            $length = [long]$_.Length
            $bytes += $length
            $files++
            $relative = $_.FullName.Substring($prefix.Length)
            $parts = @($relative -split '[\\/]')
            $group = if ($parts.Count -gt 1) { $parts[0] } else { '[files directly in profile]' }
            if (-not $groupMap.ContainsKey($group)) { $groupMap[$group] = [long]0 }
            $groupMap[$group] = [long]$groupMap[$group] + $length

            if ($parts.Count -ge 4 -and $parts[0] -eq 'AppData') {
                $appKey = "$($parts[1])\$($parts[2])"
                if (-not $appMap.ContainsKey($appKey)) { $appMap[$appKey] = [long]0 }
                $appMap[$appKey] = [long]$appMap[$appKey] + $length
            }
        }

    if ($scanErrors.Count -gt 0) {
        $warnings.Add(($strings.warnings.profile_unreadable -f $scanErrors.Count))
    }

    $groups = @($groupMap.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{ Name = $_.Key; Bytes = [long]$_.Value; GB = Convert-ToGB([long]$_.Value) }
    } | Sort-Object Bytes -Descending)
    $appGroups = @($appMap.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{ Name = $_.Key; Bytes = [long]$_.Value; GB = Convert-ToGB([long]$_.Value) }
    } | Sort-Object Bytes -Descending)

    return [pscustomobject]@{
        Path = $Path; Bytes = $bytes; Files = $files; Errors = $scanErrors.Count
        Groups = $groups; AppDataGroups = $appGroups
    }
}

function Get-GroupBytes {
    param([object[]]$Groups, [string]$Name)
    $match = @($Groups | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
    if ($match.Count -eq 0) { return [long]0 }
    return [long]$match[0].Bytes
}

function New-DataRows {
    param([object[]]$Items, [int]$Limit)
    $selected = @($Items | Where-Object { $_.Bytes -gt 0 } | Select-Object -First $Limit)
    if ($selected.Count -eq 0) { return '<p class="empty">No readable data was found.</p>' }
    $maxBytes = [double]($selected | Measure-Object Bytes -Maximum).Maximum
    $rows = foreach ($item in $selected) {
        $width = if ($maxBytes -gt 0) { [math]::Max(1, [math]::Round(100 * $item.Bytes / $maxBytes, 1)) } else { 0 }
        $label = Encode-Html $item.Name
        $path = if ($null -ne $item.PSObject.Properties['Path']) { Encode-Html $item.Path } else { '' }
        $pathHtml = if ($path) { "<small>$path</small>" } else { '' }
        "<div class='data-row'><div class='data-name'><span>$label</span>$pathHtml</div><div class='bar'><i style='width:$width%'></i></div><b>$(Convert-ToGB $item.Bytes) GB</b></div>"
    }
    return ($rows -join [Environment]::NewLine)
}

function New-CleanupCards {
    param([object[]]$Items)
    if ($Items.Count -eq 0) { return '<p class="empty">' + (Encode-Html $strings.empty_cleanup) + '</p>' }
    $cards = foreach ($item in $Items | Sort-Object Bytes -Descending) {
        $name = Encode-Html $item.Name
        $path = Encode-Html $item.Path
        $method = Encode-Html $item.Method
        $riskLabel = switch ($item.Risk) { 'safe' { $strings.risk.safe } 'caution' { $strings.risk.caution } default { $strings.risk.protected } }
        "<article class='cleanup-card $($item.Risk)'><div class='cleanup-top'><span>$riskLabel</span><b>$(Convert-ToGB $item.Bytes) GB</b></div><h3>$name</h3><code>$path</code><p>$method</p></article>"
    }
    return ($cards -join [Environment]::NewLine)
}

function New-WarningHtml {
    param([string[]]$Items)
    if ($Items.Count -eq 0) { return '<div class="notice ok"><b>' + (Encode-Html $strings.scan_quality_ok) + '</b></div>' }
    $lines = foreach ($item in $Items) { '<li>' + (Encode-Html $item) + '</li>' }
    return "<div class='notice warn'><b>$(Encode-Html $strings.scan_limitations)</b><ul>$($lines -join '')</ul></div>"
}

$isAdmin = Get-IsAdministrator
$profilePath = if ([string]::IsNullOrWhiteSpace($UserProfilePath)) { [Environment]::GetFolderPath('UserProfile') } else { [System.IO.Path]::GetFullPath($UserProfilePath) }
if (-not $profilePath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "User profile must be on drive ${root}: $profilePath" }
if (-not (Test-Path -LiteralPath $profilePath -PathType Container)) { throw "User profile not found: $profilePath" }
$isolatedProfile = ($profilePath -match '\\CodexSandbox')
$windowsPath = if ($env:windir -and $env:windir.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { $env:windir } else { Join-Path $root 'Windows' }
$programFilesPath = [Environment]::GetFolderPath('ProgramFiles')
$programFilesX86Path = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$programDataPath = [Environment]::GetFolderPath('CommonApplicationData')
$recyclePath = Join-Path $root '$Recycle.Bin'

Write-Output "Analyzing drive $root (read-only)..."
$profileTree = Get-ProfileTree $profilePath
$windowsTree = Get-GroupedTree -Path $windowsPath -GroupDepth 1 -Label 'Windows'
$programFilesTree = Get-GroupedTree -Path $programFilesPath -GroupDepth 1 -Label 'Program Files'
$programFilesX86Tree = Get-GroupedTree -Path $programFilesX86Path -GroupDepth 1 -Label 'Program Files (x86)'
$programDataTree = Get-GroupedTree -Path $programDataPath -GroupDepth 1 -Label 'ProgramData'
$recycleTree = Get-GroupedTree -Path $recyclePath -GroupDepth 1 -Label 'Recycle Bin'
$updateTree = Get-GroupedTree -Path (Join-Path $windowsPath 'SoftwareDistribution\Download') -GroupDepth 1 -Label 'Windows Update downloads'
$crashTree = Get-GroupedTree -Path (Join-Path $profilePath 'AppData\Local\CrashDumps') -GroupDepth 1 -Label 'Crash dumps'

$rootSystemBytes = [long]0
$rootSystemFiles = @()
$wantedRootFiles = @('pagefile.sys', 'hiberfil.sys', 'swapfile.sys', 'MEMORY.DMP')
$rootScanErrors = @()
$visibleRootFiles = @(Get-ChildItem -LiteralPath $root -Force -File -ErrorAction SilentlyContinue -ErrorVariable +rootScanErrors)
foreach ($file in $visibleRootFiles) {
    if ($wantedRootFiles -contains $file.Name) {
        $rootSystemBytes += [long]$file.Length
        $rootSystemFiles += [pscustomobject]@{ Name = $file.Name; Bytes = [long]$file.Length; GB = Convert-ToGB([long]$file.Length); Path = $file.FullName }
    }
}
if ($rootScanErrors.Count -gt 0) { $warnings.Add(($strings.warnings.system_file -f $root)) }

$mainCategories = @(
    [pscustomobject]@{ Name = $strings.categories.windows; Bytes = [long]$windowsTree.Bytes; GB = Convert-ToGB([long]$windowsTree.Bytes); Path = $windowsTree.Path }
    [pscustomobject]@{ Name = $strings.categories.profile; Bytes = [long]$profileTree.Bytes; GB = Convert-ToGB([long]$profileTree.Bytes); Path = $profileTree.Path }
    [pscustomobject]@{ Name = $strings.categories.program_files_x86; Bytes = [long]$programFilesX86Tree.Bytes; GB = Convert-ToGB([long]$programFilesX86Tree.Bytes); Path = $programFilesX86Tree.Path }
    [pscustomobject]@{ Name = $strings.categories.program_data; Bytes = [long]$programDataTree.Bytes; GB = Convert-ToGB([long]$programDataTree.Bytes); Path = $programDataTree.Path }
    [pscustomobject]@{ Name = $strings.categories.program_files; Bytes = [long]$programFilesTree.Bytes; GB = Convert-ToGB([long]$programFilesTree.Bytes); Path = $programFilesTree.Path }
    [pscustomobject]@{ Name = $strings.categories.root_system; Bytes = $rootSystemBytes; GB = Convert-ToGB $rootSystemBytes; Path = $root }
    [pscustomobject]@{ Name = $strings.categories.recycle_bin; Bytes = [long]$recycleTree.Bytes; GB = Convert-ToGB([long]$recycleTree.Bytes); Path = $recycleTree.Path }
)

$cleanupCandidates = New-Object System.Collections.Generic.List[object]
function Add-CleanupCandidate([string]$Name, [string]$Path, [long]$Bytes, [string]$Risk, [string]$Method) {
    if ($Bytes -gt 0) {
        $cleanupCandidates.Add([pscustomobject]@{ Name = $Name; Path = $Path; Bytes = $Bytes; GB = Convert-ToGB $Bytes; Risk = $Risk; Method = $Method })
    }
}

Add-CleanupCandidate $strings.cleanup.recycle_bin.name $recyclePath ([long]$recycleTree.Bytes) 'safe' $strings.cleanup.recycle_bin.method
Add-CleanupCandidate $strings.cleanup.temp.name (Join-Path $profilePath 'AppData\Local\Temp') (Get-GroupBytes $profileTree.AppDataGroups 'Local\Temp') 'safe' $strings.cleanup.temp.method
Add-CleanupCandidate $strings.cleanup.windows_update.name $updateTree.Path ([long]$updateTree.Bytes) 'safe' $strings.cleanup.windows_update.method
Add-CleanupCandidate $strings.cleanup.crash_dumps.name $crashTree.Path ([long]$crashTree.Bytes) 'safe' $strings.cleanup.crash_dumps.method
Add-CleanupCandidate $strings.cleanup.user_cache.name (Join-Path $profilePath '.cache') (Get-GroupBytes $profileTree.Groups '.cache') 'caution' $strings.cleanup.user_cache.method
Add-CleanupCandidate $strings.cleanup.gradle.name (Join-Path $profilePath '.gradle') (Get-GroupBytes $profileTree.Groups '.gradle') 'caution' $strings.cleanup.gradle.method
Add-CleanupCandidate $strings.cleanup.playwright.name (Join-Path $profilePath 'AppData\Local\ms-playwright') (Get-GroupBytes $profileTree.AppDataGroups 'Local\ms-playwright') 'caution' $strings.cleanup.playwright.method
Add-CleanupCandidate $strings.cleanup.downloads.name (Join-Path $profilePath 'Downloads') (Get-GroupBytes $profileTree.Groups 'Downloads') 'caution' $strings.cleanup.downloads.method

$totalBytes = [long]$drive.TotalSize
$freeBytes = [long]$drive.AvailableFreeSpace
$usedBytes = $totalBytes - $freeBytes
$usedPercent = if ($totalBytes -gt 0) { [math]::Round(100 * $usedBytes / $totalBytes, 1) } else { 0 }
$freePercent = [math]::Round(100 - $usedPercent, 1)

if (-not $isAdmin) {
    $warnings.Add($strings.warnings.not_admin)
}
if ($isolatedProfile) { $warnings.Add($strings.warnings.isolated_profile) }
$warnings.Add($strings.warnings.logical_sizes)
$warningArray = $warnings.ToArray()
$cleanupArray = $cleanupCandidates.ToArray()
$unreadableItems = [int]$profileTree.Errors + [int]$windowsTree.Errors + [int]$programFilesTree.Errors + [int]$programFilesX86Tree.Errors + [int]$programDataTree.Errors + [int]$recycleTree.Errors + [int]$updateTree.Errors + [int]$crashTree.Errors + [int]$rootScanErrors.Count

$report = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToString('o')
    drive = [ordered]@{
        letter = $driveName; root = $root; total_bytes = $totalBytes; used_bytes = $usedBytes; free_bytes = $freeBytes
        total_gb = Convert-ToGB $totalBytes; used_gb = Convert-ToGB $usedBytes; free_gb = Convert-ToGB $freeBytes
        used_percent = $usedPercent; free_percent = $freePercent
    }
    scan = [ordered]@{
        administrator = $isAdmin; current_profile = $profilePath; isolated_profile_detected = $isolatedProfile
        unreadable_items = $unreadableItems; warnings = $warningArray
    }
    main_categories = $mainCategories
    user_profile_top = @($profileTree.Groups | Select-Object -First $Top)
    appdata_top = @($profileTree.AppDataGroups | Select-Object -First $Top)
    windows_top = @($windowsTree.Groups | Select-Object -First $Top)
    program_files_top = @($programFilesTree.Groups | Select-Object -First $Top)
    program_files_x86_top = @($programFilesX86Tree.Groups | Select-Object -First $Top)
    program_data_top = @($programDataTree.Groups | Select-Object -First $Top)
    root_system_files = $rootSystemFiles
    cleanup_candidates = $cleanupArray
    protected_paths = @(
        "$windowsPath\WinSxS", "$windowsPath\System32", "$windowsPath\Installer",
        $programFilesPath, $programFilesX86Path, (Join-Path $root 'pagefile.sys'), (Join-Path $root 'hiberfil.sys')
    )
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$baseName = "windows-disk-$($driveName.ToLowerInvariant())-$stamp"
$jsonPath = Join-Path $resolvedOutput "$baseName.json"
$htmlPath = Join-Path $resolvedOutput "$baseName.html"

$json = $report | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($jsonPath, $json, $utf8NoBom)

$templatePath = Join-Path $skillRoot 'assets\report-template.html'
if (-not (Test-Path -LiteralPath $templatePath)) { throw "HTML template not found: $templatePath" }
$html = [System.IO.File]::ReadAllText($templatePath)
$statusClass = if ($freePercent -ge 20) { 'healthy' } elseif ($freePercent -ge 10) { 'warning' } else { 'critical' }
$statusText = if ($freePercent -ge 20) { $strings.status.healthy } elseif ($freePercent -ge 10) { $strings.status.warning } else { $strings.status.critical }

$replacements = [ordered]@{
    '{{DRIVE}}' = Encode-Html $driveName
    '{{GENERATED_AT}}' = Encode-Html (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    '{{TOTAL_GB}}' = [string](Convert-ToGB $totalBytes)
    '{{USED_GB}}' = [string](Convert-ToGB $usedBytes)
    '{{FREE_GB}}' = [string](Convert-ToGB $freeBytes)
    '{{USED_PERCENT}}' = [string]$usedPercent
    '{{FREE_PERCENT}}' = [string]$freePercent
    '{{STATUS_CLASS}}' = $statusClass
    '{{STATUS_TEXT}}' = $statusText
    '{{ADMIN_TEXT}}' = $(if ($isAdmin) { $strings.permission.admin } else { $strings.permission.standard })
    '{{UNREADABLE_ITEMS}}' = [string]$unreadableItems
    '{{CATEGORY_ROWS}}' = New-DataRows $mainCategories $Top
    '{{USER_ROWS}}' = New-DataRows $profileTree.Groups $Top
    '{{APPDATA_ROWS}}' = New-DataRows $profileTree.AppDataGroups $Top
    '{{WINDOWS_ROWS}}' = New-DataRows $windowsTree.Groups $Top
    '{{CLEANUP_CARDS}}' = New-CleanupCards $cleanupArray
    '{{WARNINGS}}' = New-WarningHtml $warningArray
}
foreach ($entry in $replacements.GetEnumerator()) { $html = $html.Replace($entry.Key, [string]$entry.Value) }
[System.IO.File]::WriteAllText($htmlPath, $html, $utf8NoBom)

Write-Output "HTML_REPORT=$htmlPath"
Write-Output "JSON_REPORT=$jsonPath"
Write-Output "USED_GB=$(Convert-ToGB $usedBytes)"
Write-Output "FREE_GB=$(Convert-ToGB $freeBytes)"
Write-Output "PROFILE_PATH=$profilePath"
Write-Output "UNREADABLE_ITEMS=$unreadableItems"
Write-Output "ISOLATED_PROFILE=$([int]$isolatedProfile)"
Write-Output "ADMINISTRATOR=$([int]$isAdmin)"
Write-Output "SCAN_COMPLETE=1"
