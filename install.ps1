# ============================================================================
#  VEILOPS 官方安装脚本（Windows / PowerShell，无需 Docker）
#  用法：
#     irm https://<你的地址>/install.ps1 | iex
#  可选参数： -Port 8080 -Dir C:\veilops -Base <下载源地址>
# ============================================================================
[CmdletBinding()]
param(
  [int]$Port = 8080,
  [string]$Dir = "$env:ProgramData\veilops",
  [string]$Base = "https://github.com/VEILOPS/veilops/releases/download/v1.0.0"
)

$ErrorActionPreference = "Stop"
$Version = "v1.0.0"
$Archive = "veilops-$Version-windows-amd64.zip"
$Url = ($Base.TrimEnd('/')) + "/" + $Archive

function Info($m) { Write-Host "[veilops] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[  ok  ] $m" -ForegroundColor Green }
function Fail($m) { Write-Host "[ fail ] $m" -ForegroundColor Red }

Info "下载 $Archive"
$tmp = Join-Path $env:TEMP $Archive
try {
  Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
} catch {
  Fail "下载失败：$($_.Exception.Message)"
  Fail "请检查地址是否可访问：$Url"
  return
}
Ok ("下载完成 " + [math]::Round((Get-Item $tmp).Length / 1MB, 1) + " MB")

Info "安装到 $Dir"
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Expand-Archive -Path $tmp -DestinationPath $env:TEMP -Force -ErrorAction Stop
$src = Join-Path $env:TEMP "veilops"
Copy-Item (Join-Path $src "*") $Dir -Recurse -Force
Remove-Item $src -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

$cfg = Join-Path $Dir "config.yaml"
if (-not (Test-Path $cfg) -or (Get-Item $cfg).Length -eq 0) {
  $t = Get-Content (Join-Path $Dir "config.example.yaml") -Raw -Encoding UTF8
  $t = $t -replace '(?m)^(\s{2})tls_enabled:\s*true', '${1}tls_enabled: false'
  $t = $t -replace '(?m)^(\s{2})host:\s*.*', '${1}host: 0.0.0.0'
  $t = $t -replace '(?m)^(\s{2})port:\s*8080', ('${1}port: ' + $Port)
  [IO.File]::WriteAllText($cfg, $t, (New-Object Text.UTF8Encoding($false)))
  Ok "已生成默认配置 config.yaml"
}

$exe = Join-Path $Dir "veilops.exe"
Info "启动服务（后台）"
$p = Start-Process -FilePath $exe -ArgumentList @('-config', $cfg, '--http') -WorkingDirectory $Dir -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 8

try {
  Invoke-WebRequest "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 10 | Out-Null
  Ok "VEILOPS $Version 已启动"
} catch {
  Fail "启动后无法访问，请检查 $Dir\log 或手动运行 $exe"
}

# 首启密码：从控制台输出里拿不到，提示查看方式
Write-Host ""
Write-Host "   访问地址 : http://127.0.0.1:$Port/"
Write-Host "   安装目录 : $Dir"
Write-Host "   用户名   : admin"
Write-Host "   初始密码 : 只打印一次。若没看到，可执行下面命令重置："
Write-Host "              & '$exe' -config '$cfg' -reset-admin-password"
Write-Host ""
Write-Host "   ⚠ 首次登录后请立刻改密码，并在「设置 → 基本设置」填你自己的模型 API Key。"
