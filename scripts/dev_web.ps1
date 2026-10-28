<#
本地网页试玩循环：用 http 服务 exports/web，改动后自动重新导出，页面自动刷新。
Ctrl+C 结束。

  powershell -ExecutionPolicy Bypass -File scripts\dev_web.ps1
  powershell -ExecutionPolicy Bypass -File scripts\dev_web.ps1 -Once
  powershell -ExecutionPolicy Bypass -File scripts\dev_web.ps1 -Port 8123 -NoWatch
#>
param(
  [int]$Port = 8123,
  [switch]$Once,
  [switch]$NoWatch,
  [string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$web = Join-Path $root "exports\web"

if (-not $Godot) {
  if ($env:GODOT_EXE) { $Godot = $env:GODOT_EXE }
  elseif (Test-Path "D:\Users\y00866000\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe") {
    $Godot = "D:\Users\y00866000\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe"
  } else { throw "Godot not found. Pass -Godot <path to godot console exe>." }
}

function Export-Web {
  Write-Host "[export] $(Get-Date -Format HH:mm:ss)"
  New-Item -ItemType Directory -Force -Path $web | Out-Null
  & $Godot --headless --path $root --export-release "Web" (Join-Path $web "index.html") | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Host "[export] FAILED ($LASTEXITCODE)"; return $false }
  Add-AutoReload
  return $true
}

function Add-AutoReload {
  $idx = Join-Path $web "index.html"
  if (-not (Test-Path $idx)) { return }
  $rev = [DateTime]::UtcNow.Ticks.ToString()
  [IO.File]::WriteAllText((Join-Path $web "rev.txt"), $rev, (New-Object System.Text.UTF8Encoding($false)))
  $snippet = @"
<script>
window.__rev="";
setInterval(async()=>{try{
  const r=await fetch("rev.txt?t="+Date.now(),{cache:"no-store"});
  const v=(await r.text()).trim();
  if(window.__rev&&window.__rev!==v){location.reload();}
  window.__rev=v;
}catch(e){}},1500);
</script>
"@
  $html = [IO.File]::ReadAllText($idx)
  if ($html -notmatch "window\.__rev") {
    $html = $html -replace "</body>", ($snippet + "</body>")
    [IO.File]::WriteAllText($idx, $html, (New-Object System.Text.UTF8Encoding($false)))
  }
}

function Get-Signature {
  $files = Get-ChildItem $root -Recurse -File -Include *.gd, *.tscn, *.tres, *.json, *.gdshader, *.glb, *.otf |
    Where-Object { $_.FullName -notmatch "\\\.godot\\|\\exports\\|\\dist\\|\\build\\|\\\.git\\|node_modules|\\tests\\fixtures\\" }
  ($files | ForEach-Object { "$($_.FullName)|$($_.LastWriteTimeUtc.Ticks)|$($_.Length)" }) -join "`n"
}

$listening = $false
try {
  $c = New-Object Net.Sockets.TcpClient
  $c.Connect("127.0.0.1", $Port)
  $listening = $c.Connected
  $c.Close()
} catch { }

if (-not $listening) {
  Write-Host "[serve] http://127.0.0.1:$Port/  (dir: exports\web)"
  Start-Process -FilePath "py" -ArgumentList "-3", "-m", "http.server", "$Port", "--directory", $web, "--bind", "127.0.0.1" -WindowStyle Hidden
  Start-Sleep -Seconds 2
} else {
  Write-Host "[serve] reusing http://127.0.0.1:$Port/"
}

if (-not (Test-Path (Join-Path $web "index.html"))) { Export-Web | Out-Null }
else { Add-AutoReload }
if ($Once) { Write-Host "[done] open http://127.0.0.1:$Port/"; return }

Write-Host "[watch] edit scripts/*.gd or scenes, save, then wait for re-export + browser auto-reload"
$last = Get-Signature
if (-not $NoWatch) {
  while ($true) {
    Start-Sleep -Milliseconds 800
    $now = Get-Signature
    if ($now -ne $last) {
      Start-Sleep -Milliseconds 400
      [void](Export-Web)
      $last = Get-Signature
    }
  }
}
