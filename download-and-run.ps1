# download-and-run.ps1
param(
    [string]$ConfigUrl = "https://raw.githubusercontent.com/yishuihanshang/system-config/main/system-setup.yaml"
)

Write-Host "🎯 开始自动化系统配置..." -ForegroundColor Green

# 检查是否以管理员身份运行
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ 请以管理员身份运行此脚本！" -ForegroundColor Red
    pause
    exit 1
}

# 创建临时目录
$TempDir = "$env:TEMP\SystemSetup"
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# 下载配置文件
$ConfigPath = "$TempDir\system-setup.yaml"
try {
    Write-Host "📥 下载配置文件..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $ConfigUrl -OutFile $ConfigPath
    Write-Host "✅ 配置文件下载完成" -ForegroundColor Green
}
catch {
    Write-Host "❌ 下载配置文件失败: $($_.Exception.Message)" -ForegroundColor Red
    pause
    exit 1
}

# 执行 WinGet 配置
Write-Host "🚀 开始应用系统配置..." -ForegroundColor Yellow
try {
    winget configure -f $ConfigPath --accept-configuration-agreements
    Write-Host "🎉 系统配置完成！" -ForegroundColor Green
}
catch {
    Write-Host "⚠️ 配置过程中出现错误: $($_.Exception.Message)" -ForegroundColor Red
}

# 清理临时文件
Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "✨ 所有操作已完成！" -ForegroundColor Green
pause