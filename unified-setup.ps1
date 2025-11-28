# unified-setup.ps1 - 统一配置的一键重装脚本
param(
    [string]$ConfigFile = "software-config.yaml"
)

Write-Host "🚀 开始统一配置部署..." -ForegroundColor Cyan

# 检查管理员权限
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ 请以管理员身份运行此脚本！" -ForegroundColor Red
    pause
    exit 1
}

# 内置软件配置（作为默认配置）
$DefaultConfig = @"
# 统一软件配置列表
# 只需维护这个列表，脚本会自动处理安装和重装

software:
  - id: Microsoft.OneDrive
    name: OneDrive
    uninstall_names: ["Microsoft OneDrive"]

  - id: Google.Chrome
    name: Google Chrome
    uninstall_names: ["Google Chrome"]

   - id: Tencent.QQ.NT
    name: QQ
    uninstall_names: ["QQ"]

  - id: Tencent.WeChat
    name: 微信
    uninstall_names: ["WeChat"]

  - id: Discord.Discord
    name: Discord
    uninstall_names: ["Discord"]

  - id: 7zip.7zip
    name: 7-Zip
    uninstall_names: ["7-Zip"]
    
  - id: Notepad++.Notepad++
    name: Notepad++
    uninstall_names: ["Notepad++"]

  - id: Kingsoft.WPSOffice
    name: WPS Office
    uninstall_names: ["WPS Office"]
"@

# 解析YAML配置的简单函数
function Parse-YamlConfig {
    param([string]$YamlContent)
    
    $softwareList = @()
    $lines = $YamlContent -split "`n"
    $inSoftwareSection = $false
    $currentSoftware = @{}
    
    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        
        # 跳过注释和空行
        if ($trimmedLine.StartsWith("#") -or $trimmedLine -eq "") {
            continue
        }
        
        # 检测软件列表开始
        if ($trimmedLine -eq "software:") {
            $inSoftwareSection = $true
            continue
        }
        
        if ($inSoftwareSection) {
            # 检测新软件项开始
            if ($trimmedLine.StartsWith("- id:")) {
                # 保存前一个软件项
                if ($currentSoftware.Count -gt 0) {
                    $softwareList += $currentSoftware.Clone()
                    $currentSoftware = @{}
                }
                $currentSoftware.id = $trimmedLine.Substring(5).Trim().Replace("`"", "")
            }
            # 解析其他属性
            elseif ($trimmedLine.StartsWith("name:")) {
                $currentSoftware.name = $trimmedLine.Substring(5).Trim().Replace("`"", "")
            }
            elseif ($trimmedLine.StartsWith("uninstall_names:")) {
                $namesString = $trimmedLine.Substring(16).Trim()
                $names = $namesString -replace '\[|\]|"' -split "," | ForEach-Object { $_.Trim() }
                $currentSoftware.uninstall_names = $names
            }
        }
    }
    
    # 添加最后一个软件项
    if ($currentSoftware.Count -gt 0) {
        $softwareList += $currentSoftware
    }
    
    return $softwareList
}

# 统一的软件处理函数
function Process-Software {
    param(
        [hashtable]$Software,
        [int]$Index,
        [int]$Total
    )
    
    $id = $Software.id
    $name = $Software.name
    $uninstallNames = $Software.uninstall_names
    
    Write-Host "`n📦 [$Index/$Total] 处理: $name" -ForegroundColor Yellow
    
    # 检查是否已安装
    $isInstalled = $false
    try {
        $installed = winget list --id $id --exact -s winget 2>$null
        if ($LASTEXITCODE -eq 0) {
            $isInstalled = $true
            Write-Host "⚠️  检测到已安装，执行卸载..." -ForegroundColor Magenta
        }
    } catch {
        # 忽略检查错误
    }
    
    # 如果已安装，先卸载
    if ($isInstalled) {
        try {
            # 方法1: 通过 Winget 卸载
            winget uninstall --id $id --exact -s winget --silent
            Write-Host "✅  Winget 卸载完成" -ForegroundColor Green
            Start-Sleep -Seconds 2
        } catch {
            Write-Host "⚠️  Winget 卸载失败，尝试其他方法..." -ForegroundColor Red
        }
        
        # 方法2: 通过控制面板卸载（备用）
        if ($uninstallNames) {
            foreach ($uninstallName in $uninstallNames) {
                try {
                    $uninstall = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*$uninstallName*" }
                    if ($uninstall) {
                        Write-Host "🗑️  通过控制面板卸载: $uninstallName" -ForegroundColor Magenta
                        $uninstall.Uninstall()
                        Start-Sleep -Seconds 2
                    }
                } catch {
                    # 静默处理错误
                }
            }
        }
    } else {
        Write-Host "🆕 软件未安装，直接安装..." -ForegroundColor Cyan
    }
    
    # 安装软件
    try {
        Write-Host "📥 正在安装: $name..." -ForegroundColor Green
        winget install --id $id --source winget --silent --accept-package-agreements --accept-source-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ $name 安装成功" -ForegroundColor Green
            return $true
        } else {
            Write-Host "❌ $name 安装失败" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ $name 安装异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 主执行逻辑
try {
    # 读取配置
    Write-Host "📋 读取软件配置..." -ForegroundColor Yellow
    
    if (Test-Path $ConfigFile) {
        Write-Host "📁 使用外部配置文件: $ConfigFile" -ForegroundColor Cyan
        $yamlContent = Get-Content $ConfigFile -Raw
    } else {
        Write-Host "📁 使用内置默认配置" -ForegroundColor Cyan
        $yamlContent = $DefaultConfig
        
        # 保存默认配置到文件，方便用户修改
        $DefaultConfig | Out-File -FilePath "software-config.yaml" -Encoding UTF8
        Write-Host "💡 默认配置已保存到 software-config.yaml，您可以修改此文件来自定义软件列表" -ForegroundColor Yellow
    }
    
    # 解析配置
    $softwareList = Parse-YamlConfig -YamlContent $yamlContent
    $totalSoftware = $softwareList.Count
    
    if ($totalSoftware -eq 0) {
        Write-Host "❌ 未找到有效的软件配置" -ForegroundColor Red
        pause
        exit 1
    }
    
    Write-Host "🎯 找到 $totalSoftware 个软件待处理" -ForegroundColor Green
    
    # 按顺序处理每个软件
    $successCount = 0
    $failedList = @()
    
    for ($i = 0; $i -lt $totalSoftware; $i++) {
        $software = $softwareList[$i]
        $result = Process-Software -Software $software -Index ($i + 1) -Total $totalSoftware
        
        if ($result) {
            $successCount++
        } else {
            $failedList += $software.name
        }
        
        # 短暂暂停，避免过快执行
        Start-Sleep -Milliseconds 500
    }
    
    # 显示最终结果
    Write-Host "`n" + "="*50 -ForegroundColor Cyan
    Write-Host "🎉 部署完成总结" -ForegroundColor Cyan
    Write-Host "✅ 成功安装: $successCount/$totalSoftware" -ForegroundColor Green
    
    if ($failedList.Count -gt 0) {
        Write-Host "❌ 安装失败的软件:" -ForegroundColor Red
        foreach ($failed in $failedList) {
            Write-Host "   - $failed" -ForegroundColor Red
        }
    }
    
    Write-Host "`n💡 提示:" -ForegroundColor Yellow
    Write-Host "   修改 software-config.yaml 文件可以自定义软件列表" -ForegroundColor White
    Write-Host "   下次运行本脚本时会自动使用修改后的配置" -ForegroundColor White
    
} catch {
    Write-Host "❌ 脚本执行出错: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "详细错误: $($_.ScriptStackTrace)" -ForegroundColor Red
}

Write-Host "`n✨ 脚本执行完毕" -ForegroundColor Cyan
pause