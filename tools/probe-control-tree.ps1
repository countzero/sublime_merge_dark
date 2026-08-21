<#
.SYNOPSIS
    Reads Sublime Merge's control tree for a given pixel, to find out which theme class
    paints it.

.DESCRIPTION
    Requires "log_control_tree": true in Packages/User/Preferences.sublime-settings.
    The script focuses Merge, ctrl+alt+clicks the target pixel (which makes Merge log the
    control tree for whatever is under the cursor), toggles the console open with ctrl+`,
    and saves both a full-window capture and a magnified crop of the console area.

    Remove the log_control_tree setting when you are done.

.PARAMETER FracX
    Horizontal click position as a fraction of window width.

.PARAMETER FracY
    Vertical click position as a fraction of window height.

.PARAMETER Label
    Filename prefix for the two PNGs written to -OutputDir.

.PARAMETER OutputDir
    Where to write the captures. Defaults to the directory holding this script.
#>
[CmdletBinding()]
param(
    [double]$FracX = 0.70,
    [double]$FracY = 0.93,
    [string]$Label = 'TREE',
    [string]$OutputDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

if (-not $OutputDir) { $OutputDir = (Get-Location).Path }
$null = New-Item -ItemType Directory -Path $OutputDir -Force

Add-Type -AssemblyName System.Drawing
if (-not ('Native.Tr' -as [type])) {
    Add-Type -Namespace Native -Name Tr -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out System.Drawing.Rectangle r);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
'@ -ReferencedAssemblies System.Drawing.Primitives
}

$procs = @(Get-Process -Name sublime_merge -ErrorAction SilentlyContinue |
           Where-Object { $_.MainWindowHandle -ne 0 })
if ($procs.Count -eq 0) { throw 'Sublime Merge is not running (no process with a main window).' }
if ($procs.Count -gt 1) {
    throw "Found $($procs.Count) Sublime Merge windows. Close all but the one you want to probe."
}
$h = $procs[0].MainWindowHandle
$tid = [Native.Tr]::GetWindowThreadProcessId($h, [IntPtr]::Zero)

# GetWindowRect fills a Win32 RECT (left/top/right/bottom), but it is marshalled here into
# a System.Drawing.Rectangle (x/y/width/height). The field names therefore lie: .Width
# holds "right" and .Height holds "bottom". Hence the subtractions below. Do not "fix" this
# without also changing the P/Invoke signature to a real RECT struct.
$r = New-Object System.Drawing.Rectangle
for ($attempt = 1; $attempt -le 6; $attempt++) {
    if ($attempt -gt 1) {
        # minimise then restore: reliably grants foreground when SetForegroundWindow is
        # refused, which Windows does for a process not already in the foreground
        [Native.Tr]::ShowWindow($h, 6) | Out-Null
        Start-Sleep -Milliseconds 600
    }
    [Native.Tr]::ShowWindow($h, 9) | Out-Null
    Start-Sleep -Milliseconds 700
    [Native.Tr]::AttachThreadInput([Native.Tr]::GetCurrentThreadId(), $tid, $true) | Out-Null
    [Native.Tr]::SetForegroundWindow($h) | Out-Null
    [Native.Tr]::BringWindowToTop($h) | Out-Null
    [Native.Tr]::AttachThreadInput([Native.Tr]::GetCurrentThreadId(), $tid, $false) | Out-Null
    Start-Sleep -Milliseconds 900
    [Native.Tr]::GetWindowRect($h, [ref]$r) | Out-Null
    $focused = ([Native.Tr]::GetForegroundWindow() -eq $h)
    Write-Output ("  attempt {0}: focused={1} size={2}x{3}" -f `
        $attempt, $focused, ($r.Width - $r.X), ($r.Height - $r.Y))
    if ($focused -and (($r.Width - $r.X) -gt 600)) { break }
}
$w = $r.Width - $r.X; $ht = $r.Height - $r.Y
if ($w -lt 600) { throw 'Could not focus and restore the Sublime Merge window.' }

function Get-WindowCapture {
    param([IntPtr]$Handle, [int]$Width, [int]$Height)
    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $hdc = $g.GetHdc()
        try { [Native.Tr]::PrintWindow($Handle, $hdc, 2) | Out-Null } finally { $g.ReleaseHdc($hdc) }
    } finally { $g.Dispose() }
    return $bmp
}

# fraction of sampled pixels that differ between two captures, within a bottom band
function Get-BandDelta {
    param($A, $B, [double]$BandFrac = 0.35)
    $y0 = [int]($A.Height * (1.0 - $BandFrac))
    $diff = 0; $seen = 0
    for ($y = $y0; $y -lt $A.Height; $y += 4) {
        for ($x = 0; $x -lt $A.Width; $x += 4) {
            $seen++
            if ($A.GetPixel($x, $y).ToArgb() -ne $B.GetPixel($x, $y).ToArgb()) { $diff++ }
        }
    }
    if ($seen -eq 0) { return 0.0 }
    return ($diff / $seen)
}

$cx = [int]($w * $FracX); $cy = [int]($ht * $FracY)
$before = $null; $after = $null; $crop = $null
try {
    $before = Get-WindowCapture -Handle $h -Width $w -Height $ht
    $c = $before.GetPixel($cx, $cy)
    Write-Output ("  target pixel ({0},{1}) = #{2:X2}{3:X2}{4:X2}" -f $cx, $cy, $c.R, $c.G, $c.B)

    $VK_CONTROL = 0x11; $VK_MENU = 0x12; $KEYUP = 0x0002
    [Native.Tr]::SetCursorPos(($r.X + $cx), ($r.Y + $cy)) | Out-Null
    Start-Sleep -Milliseconds 500
    [Native.Tr]::keybd_event($VK_CONTROL, 0x1D, 0, [IntPtr]::Zero)
    [Native.Tr]::keybd_event($VK_MENU, 0x38, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 250
    [Native.Tr]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 150
    [Native.Tr]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 250
    [Native.Tr]::keybd_event($VK_MENU, 0x38, $KEYUP, [IntPtr]::Zero)
    [Native.Tr]::keybd_event($VK_CONTROL, 0x1D, $KEYUP, [IntPtr]::Zero)
    Write-Output '  ctrl+alt+click sent'
    Start-Sleep -Seconds 2

    # ctrl+` toggles the console. Scan code 0x29 is passed explicitly because VK_OEM_3 is
    # not the grave key on every keyboard layout.
    [Native.Tr]::keybd_event($VK_CONTROL, 0x1D, 0, [IntPtr]::Zero)
    [Native.Tr]::keybd_event(0xC0, 0x29, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 200
    [Native.Tr]::keybd_event(0xC0, 0x29, $KEYUP, [IntPtr]::Zero)
    [Native.Tr]::keybd_event($VK_CONTROL, 0x1D, $KEYUP, [IntPtr]::Zero)
    Write-Output '  ctrl+backtick sent'
    Start-Sleep -Seconds 3

    $after = Get-WindowCapture -Handle $h -Width $w -Height $ht

    # The console is a toggle and Sublime Merge remembers its state across restarts, so a
    # single keypress can just as easily close an already-open console. Detect that instead
    # of silently saving a capture with no console in it.
    $delta = Get-BandDelta -A $before -B $after
    Write-Output ("  bottom-band change after toggle: {0:P1}" -f $delta)
    if ($delta -lt 0.05) {
        Write-Warning ('The console did not appear in this capture. Either it was already ' +
                       'open and the keypress closed it, or the keypress did not reach the ' +
                       'window. Re-run to toggle it the other way.')
    }

    $after.Save((Join-Path $OutputDir "$Label.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $ch = [int]($ht * 0.36)
    $crop = New-Object System.Drawing.Bitmap(($w * 2), ($ch * 2))
    $g3 = [System.Drawing.Graphics]::FromImage($crop)
    try {
        $g3.InterpolationMode = 'NearestNeighbor'
        $g3.DrawImage($after,
            (New-Object System.Drawing.Rectangle(0, 0, ($w * 2), ($ch * 2))),
            (New-Object System.Drawing.Rectangle(0, ($ht - $ch), $w, $ch)), 'Pixel')
    } finally { $g3.Dispose() }
    $crop.Save((Join-Path $OutputDir "$Label-console.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    Write-Output "  saved $Label.png and $Label-console.png to $OutputDir"
} finally {
    if ($before) { $before.Dispose() }
    if ($after)  { $after.Dispose() }
    if ($crop)   { $crop.Dispose() }
}