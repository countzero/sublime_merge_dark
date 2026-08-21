param(
    [double]$FracX = 0.70,
    [double]$FracY = 0.93,
    [string]$Label = 'TREE'
)

$scratch = "D:\Arbeit\fertilizer_management\.tmp\sessions\ses_fdf265fcdffe3REn7y1iMIYwhM"

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

$h = (Get-Process -Name sublime_merge).MainWindowHandle
$tid = [Native.Tr]::GetWindowThreadProcessId($h, [IntPtr]::Zero)

$r = New-Object System.Drawing.Rectangle
$focused = $false
for ($attempt = 1; $attempt -le 6; $attempt++) {
    if ($attempt -gt 1) {
        [Native.Tr]::ShowWindow($h, 6) | Out-Null  # SW_MINIMIZE, then restore: reliably grants foreground
        Start-Sleep -Milliseconds 600
    }
    [Native.Tr]::ShowWindow($h, 9) | Out-Null      # SW_RESTORE
    Start-Sleep -Milliseconds 700
    [Native.Tr]::AttachThreadInput([Native.Tr]::GetCurrentThreadId(), $tid, $true) | Out-Null
    [Native.Tr]::SetForegroundWindow($h) | Out-Null
    [Native.Tr]::BringWindowToTop($h) | Out-Null
    [Native.Tr]::AttachThreadInput([Native.Tr]::GetCurrentThreadId(), $tid, $false) | Out-Null
    Start-Sleep -Milliseconds 900
    [Native.Tr]::GetWindowRect($h, [ref]$r) | Out-Null
    $focused = ([Native.Tr]::GetForegroundWindow() -eq $h)
    $bigEnough = (($r.Width - $r.X) -gt 600)
    Write-Output "  attempt ${attempt}: focused=$focused size=$($r.Width - $r.X)x$($r.Height - $r.Y)"
    if ($focused -and $bigEnough) { break }
}
$w = $r.Width - $r.X; $ht = $r.Height - $r.Y
if ($w -lt 600) { Write-Output "ABORT: window not restored"; return }
$cx = [int]($w * $FracX); $cy = [int]($ht * $FracY)

$pre = New-Object System.Drawing.Bitmap($w, $ht)
$gp = [System.Drawing.Graphics]::FromImage($pre); $hp = $gp.GetHdc()
[Native.Tr]::PrintWindow($h, $hp, 2) | Out-Null; $gp.ReleaseHdc($hp)
$c = $pre.GetPixel($cx, $cy)
Write-Output "target pixel (${cx},${cy}) = #$('{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B)"
$gp.Dispose(); $pre.Dispose()

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
Write-Output "ctrl+alt+click sent"
Start-Sleep -Seconds 2

# ctrl+` with an explicit scan code for the grave key
[Native.Tr]::keybd_event($VK_CONTROL, 0x1D, 0, [IntPtr]::Zero)
[Native.Tr]::keybd_event(0xC0, 0x29, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 200
[Native.Tr]::keybd_event(0xC0, 0x29, $KEYUP, [IntPtr]::Zero)
[Native.Tr]::keybd_event($VK_CONTROL, 0x1D, $KEYUP, [IntPtr]::Zero)
Write-Output "ctrl+backtick sent"
Start-Sleep -Seconds 3

$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g2 = [System.Drawing.Graphics]::FromImage($bmp); $hdc2 = $g2.GetHdc()
[Native.Tr]::PrintWindow($h, $hdc2, 2) | Out-Null; $g2.ReleaseHdc($hdc2)
$bmp.Save("$scratch\$Label.png", [System.Drawing.Imaging.ImageFormat]::Png)

$ch = [int]($ht * 0.36)
$crop = New-Object System.Drawing.Bitmap(($w * 2), ($ch * 2))
$g3 = [System.Drawing.Graphics]::FromImage($crop)
$g3.InterpolationMode = 'NearestNeighbor'
$g3.DrawImage($bmp, (New-Object System.Drawing.Rectangle(0, 0, ($w * 2), ($ch * 2))),
    (New-Object System.Drawing.Rectangle(0, ($ht - $ch), $w, $ch)), 'Pixel')
$g3.Dispose()
$crop.Save("$scratch\$Label-console.png", [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output "saved $Label.png and $Label-console.png"
$g2.Dispose(); $bmp.Dispose(); $crop.Dispose()
