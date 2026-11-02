
<#
.SYNOPSIS
  桌面级 UI 兜底：不依赖模组桥，直接对窗口截图 / 点击 / 按键。

.DESCRIPTION
  桥没起来（模组没加载、心跳等不到）时，用这条路继续验证界面：
  按窗口标题找进程 → 截该窗口 → 在窗口内坐标点击 / 发键。

.EXAMPLE
  .\win-ui.ps1 -Action Shot  -Title 'Terraria' -Out C:\temp\game.png
  .\win-ui.ps1 -Action Click -Title 'Terraria' -X 400 -Y 300
  .\win-ui.ps1 -Action Key   -Title 'Terraria' -Keys '{ESC}'
#>
[CmdletBinding(PositionalBinding = $false)]
param(
	[ValidateSet('List', 'Shot', 'Click', 'Key')][string]$Action = 'List',
	[string]$Title = 'Terraria|泰拉瑞亚|tModLoader',
	[string]$Out = '',
	[int]$X = -1,
	[int]$Y = -1,
	[string]$Keys = '',
	[string]$Button = 'left',
	[switch]$Focus,      # 明确要求把窗口拉到前台（默认不抢焦点）
	[switch]$NoFocus
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

# ★ 必须先声明 DPI 感知：否则 Windows 会把窗口尺寸虚拟化（168 DPI ≈ 1.75x），
#   GetWindowRect 返回的是缩小后的值，截图只拍到左上角一小块（实测 800x720 窗口只截到 471x448）。
try {
	Add-Type -Namespace WinUi -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
	if (-not [WinUi.Dpi]::SetProcessDpiAwarenessContext([IntPtr](-4))) { [void][WinUi.Dpi]::SetProcessDPIAware() }
} catch { }

Add-Type -Namespace WinUi -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
public struct RECT { public int Left, Top, Right, Bottom; }
'@

function Get-TargetWindow([string]$pattern) {
	# 标题可能被本地化成「泰拉瑞亚…」，进程名却是 dotnet，所以标题与进程名都匹配
	$noise = 'msedge|chrome|firefox|brave|opera|WindowsTerminal|pwsh|powershell|conhost|Code|devenv|DeepSeek'
	$procs = Get-Process | Where-Object {
		$_.MainWindowHandle -ne [IntPtr]::Zero -and
		$_.ProcessName -notmatch $noise -and
		($_.MainWindowTitle -match $pattern -or $_.ProcessName -match $pattern)
	} | Sort-Object @{ Expression = {
		# 游戏客户端：dotnet 进程 + 标题像游戏（不是 Server 控制台）
		if ($_.ProcessName -eq 'dotnet' -and $_.MainWindowTitle -match '泰拉瑞亚|Terraria' -and $_.MainWindowTitle -notmatch 'Server|服务器') { 0 }
		elseif ($_.ProcessName -eq 'dotnet' -and $_.MainWindowTitle -notmatch 'Server|服务器') { 1 }
		else { 2 }
	} }, Id
	if (-not $procs) { return @() }
	return @($procs | ForEach-Object {
		[PSCustomObject]@{ Pid = $_.Id; Name = $_.ProcessName; Title = $_.MainWindowTitle; Handle = $_.MainWindowHandle }
	})
}

if ($Action -eq 'List') {
	$all = Get-Process | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
		Select-Object Id, ProcessName, MainWindowTitle | Sort-Object ProcessName
	$all | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
	exit 0
}

$target = Get-TargetWindow $Title
if ($target.Count -eq 0) { Write-Error "找不到标题匹配 '$Title' 的窗口（先 -Action List 看看）"; exit 2 }
$win = $target[0]
Write-Host ("target: pid={0} name={1} title='{2}'" -f $win.Pid, $win.Name, $win.Title)

# 默认不动焦点：截图走 PrintWindow，被遮挡也能拍，没必要把窗口拉到前台。
# 只有显式 -Focus，或 -Action Key（SendKeys 必须有前台焦点）时才激活。
$needFocus = ($Focus -or $Action -eq 'Key') -and (-not $NoFocus)
if ($needFocus) {
	if ([WinUi.Native]::IsIconic($win.Handle)) { [void][WinUi.Native]::ShowWindow($win.Handle, 9) }   # SW_RESTORE
	[void][WinUi.Native]::SetForegroundWindow($win.Handle)
	Start-Sleep -Milliseconds 250
} elseif ([WinUi.Native]::IsIconic($win.Handle)) {
	# 最小化时 PrintWindow 拍不到内容：还原但不激活
	[void][WinUi.Native]::ShowWindow($win.Handle, 4)   # 4 = SW_SHOWNOACTIVATE
	Start-Sleep -Milliseconds 120
}

$rect = New-Object WinUi.Native+RECT
[void][WinUi.Native]::GetWindowRect($win.Handle, [ref]$rect)
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
Write-Host ("window rect: {0},{1} {2}x{3}" -f $rect.Left, $rect.Top, $w, $h)

switch ($Action) {
	'Shot' {
		if (-not $Out) { $Out = Join-Path $env:TEMP ('winui-' + (Get-Date -Format 'HHmmss') + '.png') }
		$bmp = New-Object System.Drawing.Bitmap $w, $h
		$g = [System.Drawing.Graphics]::FromImage($bmp)
		# 先试 PrintWindow（窗口被遮挡也能拍到），失败再退回屏幕抓取
		$hdc = $g.GetHdc()
		$ok = [WinUi.Native]::PrintWindow($win.Handle, $hdc, 2)
		$g.ReleaseHdc($hdc)
		if (-not $ok) {
			$g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
		}
		$g.Dispose()
		$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
		$bmp.Dispose()
		Write-Host ("shot saved: {0}" -f $Out)
	}
	'Click' {
		if ($X -lt 0 -or $Y -lt 0) { Write-Error 'Click 需要 -X -Y（窗口内坐标）'; exit 2 }
		[void][WinUi.Native]::SetCursorPos($rect.Left + $X, $rect.Top + $Y)
		Start-Sleep -Milliseconds 120
		$down = if ($Button -eq 'right') { 0x0008 } else { 0x0002 }
		$up = if ($Button -eq 'right') { 0x0010 } else { 0x0004 }
		[WinUi.Native]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
		Start-Sleep -Milliseconds 60
		[WinUi.Native]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
		Write-Host ("click {0} at window({1},{2}) = screen({3},{4})" -f $Button, $X, $Y, ($rect.Left + $X), ($rect.Top + $Y))
	}
	'Key' {
		if (-not $Keys) { Write-Error 'Key 需要 -Keys'; exit 2 }
		[System.Windows.Forms.SendKeys]::SendWait($Keys)
		Write-Host ("keys sent: {0}" -f $Keys)
	}
}
