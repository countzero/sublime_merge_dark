<#
.SYNOPSIS
    Applies the Monokai Pro theme to an unregistered Sublime Merge on Windows, including the
    three surfaces that no theme rule reaches on its own.

.DESCRIPTION
    Sublime Merge gates the "theme" setting behind a licence, so the active theme is always
    named "Merge" (which is the LIGHT theme). Loose files under
    %AppData%\Sublime Merge\Packages\<PackageName>\ replace same-named resources inside the
    shipped .sublime-package archives, and that is NOT gated. This script exploits that.

    Three surfaces need special handling because Sublime Merge draws their layer0 itself,
    from the light companion colour scheme, ignoring every theme rule:
        header                        -> the app bar / toolbar
        details_panel                 -> the right-hand pane behind the diffs
        commit_dialog_summary_container -> the commit dialog pane
    For the first two, the fix is to tint their linear_container_control child, which covers
    the same rectangle and does obey the theme.

    Idempotent: safe to re-run. Re-run it after a Sublime Merge upgrade, because two of the
    files it writes are extracted from the installed version's own package.

.PARAMETER MergeProgramDir
    Sublime Merge install directory. Defaults to the standard location.

.PARAMETER Variant
    Which Monokai Pro filter to use, e.g. 'Monokai Plus', 'Monokai Plus (Octagon)'.

.PARAMETER Uninstall
    Removes every file this script creates, restoring the stock appearance.
#>
[CmdletBinding()]
param(
    [string]$MergeProgramDir = "$env:ProgramFiles\Sublime Merge",
    [string]$Variant = 'Monokai Plus',
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$packages = Join-Path $env:APPDATA 'Sublime Merge\Packages'
$themeDir = Join-Path $packages 'Theme - Merge'
$userDir  = Join-Path $packages 'User'
$cloneDir = Join-Path $packages 'Monokai Theme'
$schemeName = "$Variant Merge.sublime-color-scheme"

function Write-Step { param([string]$Message) Write-Host "  $Message" -ForegroundColor Cyan }

# ---------------------------------------------------------------- uninstall
if ($Uninstall) {
    $targets = @(
        (Join-Path $themeDir 'Merge.sublime-theme'),
        (Join-Path $themeDir 'Merge Base.sublime-theme'),
        (Join-Path $themeDir 'Merge Dark Base.sublime-theme'),
        (Join-Path $themeDir 'Widget - Merge.hidden-color-scheme'),
        (Join-Path $themeDir 'Widget - Merge.sublime-settings'),
        (Join-Path $userDir  $schemeName),
        (Join-Path $userDir  'Diff.sublime-settings'),
        (Join-Path $userDir  'Diff - Merge.sublime-settings'),
        (Join-Path $userDir  'File Mode - Merge.sublime-settings'),
        (Join-Path $userDir  'Git Output - Merge.sublime-settings'),
        (Join-Path $userDir  'Commit Message - Merge.sublime-settings'),
        (Join-Path $userDir  'Commit Message (Read Only) - Merge.sublime-settings')
    )
    foreach ($t in $targets) {
        if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force; Write-Step "removed $(Split-Path $t -Leaf)" }
    }
    Write-Host "Uninstalled. Restart Sublime Merge. ('Monokai Theme' clone and Preferences left alone.)" -ForegroundColor Green
    return
}

# ---------------------------------------------------------------- preflight
$pkgFile = Join-Path $MergeProgramDir 'Packages\Theme - Merge.sublime-package'
if (-not (Test-Path -LiteralPath $pkgFile)) {
    throw "Could not find '$pkgFile'. Pass -MergeProgramDir with the correct install path."
}
New-Item -ItemType Directory -Path $themeDir, $userDir -Force | Out-Null

# ------------------------------------------- 1. upstream Monokai theme source
if (-not (Test-Path -LiteralPath (Join-Path $cloneDir 'common'))) {
    Write-Step 'cloning bitsper2nd/merge-monokai-theme'
    git clone --quiet --depth 1 https://github.com/bitsper2nd/merge-monokai-theme.git $cloneDir
} else {
    Write-Step 'upstream Monokai clone already present'
}
$upstreamTheme  = Join-Path $cloneDir "common\$Variant.hidden-theme"
$upstreamScheme = Join-Path $cloneDir "Plus - Monokai\$Variant.sublime-color-scheme"
foreach ($f in @($upstreamTheme, $upstreamScheme)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "Upstream file missing: $f (check -Variant)" }
}

# --------------------- 2. extract the shipped themes under non-clashing names
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($pkgFile)
try {
    function Read-Entry {
        param([string]$Name)
        $entry = $zip.Entries | Where-Object { $_.FullName -eq $Name }
        if (-not $entry) { throw "'$Name' not found inside the theme package." }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { return $reader.ReadToEnd() } finally { $reader.Close() }
    }
    # the shipped LIGHT theme is the root of the inheritance chain
    [System.IO.File]::WriteAllText((Join-Path $themeDir 'Merge Base.sublime-theme'), (Read-Entry 'Merge.sublime-theme'))
    $darkBase = (Read-Entry 'Merge Dark.sublime-theme') -replace
        '"extends"\s*:\s*"Merge\.sublime-theme"', '"extends": "Merge Base.sublime-theme"'
    [System.IO.File]::WriteAllText((Join-Path $themeDir 'Merge Dark Base.sublime-theme'), $darkBase)
    Write-Step 'extracted Merge Base + Merge Dark Base from the installed package'
} finally { $zip.Dispose() }

# ------- 3. colour scheme with LITERAL globals (var() indirection breaks theme colours)
$schemeText = [System.IO.File]::ReadAllText($upstreamScheme)
$vi = $schemeText.IndexOf('"variables"'); $gi = $schemeText.IndexOf('"globals"'); $ri = $schemeText.IndexOf('"rules"')
if ($vi -lt 0 -or $gi -lt 0 -or $ri -lt 0) { throw 'Unexpected colour scheme layout.' }
$vars = @{}
foreach ($m in [regex]::Matches($schemeText.Substring($vi, $gi - $vi), '"([A-Za-z0-9_\-]+)"\s*:\s*"([^"]+)"')) {
    $vars[$m.Groups[1].Value] = $m.Groups[2].Value
}
function Resolve-SchemeVar {
    param([string]$Value)
    for ($i = 0; $i -lt 8; $i++) {
        $next = [regex]::Replace($Value, 'var\(([A-Za-z0-9_\-]+)\)', {
            param($m) $k = $m.Groups[1].Value
            if ($vars.ContainsKey($k)) { $vars[$k] } else { $m.Value } })
        if ($next -eq $Value) { break }
        $Value = $next
    }
    return $Value
}
$globalsBlock = $schemeText.Substring($gi, $ri - $gi)
$newGlobals = [regex]::Replace($globalsBlock, '("([A-Za-z0-9_]+)"\s*:\s*")([^"]+)(")', {
    param($m) $m.Groups[1].Value + (Resolve-SchemeVar $m.Groups[3].Value) + $m.Groups[4].Value })
$scheme = $schemeText.Substring(0, $gi) + $newGlobals + $schemeText.Substring($ri)
$scheme = $scheme -replace '"name"\s*:\s*"[^"]*"', "`"name`": `"$Variant Merge`""
[System.IO.File]::WriteAllText((Join-Path $userDir $schemeName), $scheme)

$background = Resolve-SchemeVar 'var(background)'
$foreground = Resolve-SchemeVar 'var(foreground)'
$selection  = Resolve-SchemeVar 'var(selection)'
$comment    = Resolve-SchemeVar 'var(comment)'
Write-Step "generated '$schemeName' (background $background)"

# ------------------------ 4. the Monokai theme itself, plus the three fixes
$theme = [System.IO.File]::ReadAllText($upstreamTheme)
$theme = $theme -replace '"extends"\s*:\s*"Merge\.sublime-theme"', '"extends": "Merge Dark Base.sublime-theme"'
$lines = [System.Collections.Generic.List[string]]($theme -split "`r?`n")
$close = -1
for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match '^\s{0,4}\]\s*$') { $close = $i; break } }
if ($close -lt 0) { throw 'Could not locate the rules array terminator in the upstream theme.' }
$prev = $close - 1
while ($lines[$prev].Trim() -eq '') { $prev-- }
if ($lines[$prev].TrimEnd() -notmatch ',$') { $lines[$prev] = $lines[$prev].TrimEnd() + ',' }
$fixes = @(
    '        // Sublime Merge draws header.layer0 and details_panel.layer0 itself, from the light',
    '        // companion colour scheme, ignoring every theme rule. Their linear_container_control',
    '        // child covers the same rectangle and does obey the theme.',
    ('        {{ "class": "linear_container_control", "parents": [{{"class": "details_panel"}}], "layer0.tint": "{0}", "layer0.opacity": 1.0 }},' -f $background),
    ('        {{ "class": "linear_container_control", "parents": [{{"class": "header"}}], "layer0.tint": "{0}", "layer0.opacity": 1.0 }},' -f $background),
    '        // without this the header content_margin leaves a 2px light line above and below',
    '        { "class": "header", "content_margin": 0 },',
    ('        {{ "class": "commit_dialog_summary_container", "layer0.tint": "{0}", "layer0.opacity": 1.0 }}' -f $background)
)
$lines.InsertRange($close, [string[]]$fixes)
$themeOut = $lines -join "`n"

# fail loudly rather than leaving a broken theme behind
$probe = ($themeOut -replace '(?m)//.*$', '')
$probe = [regex]::Replace($probe, ',(\s*[\}\]])', '$1')
try { $null = $probe | ConvertFrom-Json } catch { throw "Generated theme is not valid JSON: $($_.Exception.Message)" }
[System.IO.File]::WriteAllText((Join-Path $themeDir 'Merge.sublime-theme'), $themeOut)
Write-Step 'wrote Merge.sublime-theme (Monokai + the three surface fixes)'

# ------------------------------------------------- 5. widget palette + bindings
$widget = @"
{
	"name": "Sublime Merge Widgets",
	"globals":
	{
		"foreground": "$foreground",
		"background": "$background",
		"caret": "$foreground",
		"line_highlight": "$selection",
		"selection": "$selection",
		"selection_border": "$comment",
		"inactive_selection": "$selection"
	},
	"rules": []
}
"@
[System.IO.File]::WriteAllText((Join-Path $themeDir 'Widget - Merge.hidden-color-scheme'), $widget)
@"
{
	"color_scheme": "Widget - Merge.hidden-color-scheme",
	"draw_shadows": false
}
"@ | Set-Content -LiteralPath (Join-Path $themeDir 'Widget - Merge.sublime-settings') -Encoding UTF8

# every view type Merge binds by "<Type> - <ThemeName>.sublime-settings", plus the
# un-suffixed Diff.sublime-settings the theme docs name as the source of theme colours
$plain = @('Diff', 'Diff - Merge', 'File Mode - Merge', 'Git Output - Merge')
foreach ($n in $plain) {
    "{`n`t`"color_scheme`": `"$schemeName`"`n}" | Set-Content -LiteralPath (Join-Path $userDir "$n.sublime-settings") -Encoding UTF8
}
foreach ($n in @('Commit Message - Merge', 'Commit Message (Read Only) - Merge')) {
    "{`n`t`"color_scheme`": `"$schemeName`",`n`t`"syntax`": `"Packages/Git Formats/Git Commit.sublime-syntax`"`n}" |
        Set-Content -LiteralPath (Join-Path $userDir "$n.sublime-settings") -Encoding UTF8
}
Write-Step "bound $($plain.Count + 3) view types to the scheme"

# ---------------------------------------------- 6. global colour scheme preference
$prefsPath = Join-Path $userDir 'Preferences.sublime-settings'
$prefs = @{}
if (Test-Path -LiteralPath $prefsPath) {
    $raw = (Get-Content -LiteralPath $prefsPath -Raw) -replace '(?m)//.*$', ''
    if ($raw.Trim()) {
        try { ((ConvertFrom-Json $raw).PSObject.Properties) | ForEach-Object { $prefs[$_.Name] = $_.Value } } catch { }
    }
}
$prefs['color_scheme'] = $schemeName
($prefs | ConvertTo-Json) | Set-Content -LiteralPath $prefsPath -Encoding UTF8
Write-Step 'set the global color_scheme preference'

Write-Host ''
Write-Host 'Done. Restart Sublime Merge.' -ForegroundColor Green
Write-Host 'Re-run after a Sublime Merge upgrade: two files are extracted from the installed package.' -ForegroundColor Yellow
