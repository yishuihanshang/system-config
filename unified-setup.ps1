# unified-setup.ps1 - 统一配置的一键重装脚本

Write-Host "🚀 开始统一配置部署..." -ForegroundColor Cyan

# 检查管理员权限
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ 请以管理员身份运行此脚本！" -ForegroundColor Red
    pause
    exit 1
}

# 内置软件配置
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

  - id: Tencent.QQ
    name: QQ
    uninstall_names: ["腾讯QQ"]

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

# 显示下载进度的函数
function Show-DownloadProgress {
    param(
        [string]$SoftwareName,
        [int]$TimeoutSeconds = 600
    )
    
    Write-Host "📥 开始下载: $SoftwareName..." -ForegroundColor Cyan
    
    $startTime = Get-Date
    $dots = 0
    $maxDots = 3
    
    # 显示下载动画，直到超时
    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        $dots = ($dots + 1) % ($maxDots + 1)
        $progress = "." * $dots + " " * ($maxDots - $dots)
        Write-Host "`r🔄 下载中$progress" -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
    
    Write-Host ""  # 换行
}

# 带进度显示的安装函数
function Install-WithProgress {
    param(
        [string]$SoftwareId,
        [string]$SoftwareName,
        [int]$TimeoutSeconds = 600
    )
    
    Write-Host "📥 开始安装: $SoftwareName..." -ForegroundColor Green
    
    try {
        # 创建后台作业执行安装
        $jobScript = {
            param($id)
            $process = Start-Process -FilePath "winget" -ArgumentList @(
                "install", "--id", $id, "--source", "winget", "--silent",
                "--disable-interactivity", "--accept-package-agreements", "--accept-source-agreements"
            ) -PassThru -NoNewWindow -Wait
            return @{
                ExitCode = $process.ExitCode
                Success = ($process.ExitCode -eq 0)
            }
        }
        
        $job = Start-Job -ScriptBlock $jobScript -ArgumentList $SoftwareId
        
        # 显示安装进度动画
        $startTime = Get-Date
        $dots = 0
        $maxDots = 3
        $phase = 1  # 1=下载, 2=安装
        
        while ($job.State -eq "Running" -and ((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
            $dots = ($dots + 1) % ($maxDots + 1)
            $progress = "." * $dots + " " * ($maxDots - $dots)
            
            # 根据时间切换阶段提示（前2/3时间显示下载，后1/3显示安装）
            $elapsed = ((Get-Date) - $startTime).TotalSeconds
            if ($elapsed -lt ($TimeoutSeconds * 2 / 3)) {
                if ($phase -ne 1) {
                    Write-Host "`n✅ 下载完成，开始安装..." -ForegroundColor Green
                    $phase = 2
                }
                Write-Host "`r🌐 下载中$progress" -NoNewline -ForegroundColor Cyan
            } else {
                if ($phase -ne 2) {
                    Write-Host "`n🔄 开始安装..." -ForegroundColor Yellow
                    $phase = 2
                }
                Write-Host "`r🔧 安装中$progress" -NoNewline -ForegroundColor Yellow
            }
            
            Start-Sleep -Seconds 1
        }
        
        Write-Host ""  # 换行
        
        if ($job.State -eq "Running") {
            # 超时处理
            Write-Host "⏰ $SoftwareName 安装超时，强制终止..." -ForegroundColor Red
            Remove-Job $job -Force
            return $false
        } else {
            # 获取安装结果
            $result = Receive-Job $job
            Remove-Job $job -Force
            
            if ($result.Success) {
                Write-Host "✅ $SoftwareName 下载并安装成功" -ForegroundColor Green
                return $true
            } else {
                Write-Host "❌ $SoftwareName 安装失败，退出代码: $($result.ExitCode)" -ForegroundColor Red
                
                # 根据退出代码提供更多信息
                switch ($result.ExitCode) {
                    0x8A150011 { Write-Host "💡 提示: 软件可能已安装或存在冲突" -ForegroundColor Yellow }
                    0x8A150004 { Write-Host "💡 提示: 找不到指定的软件包" -ForegroundColor Yellow }
                    default { Write-Host "💡 提示: 请检查网络连接和系统权限" -ForegroundColor Yellow }
                }
                
                return $false
            }
        }
    } catch {
        Write-Host "❌ $SoftwareName 安装异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
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
            Write-Host "🗑️  正在卸载: $name..." -ForegroundColor Magenta
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
    
    # 使用带进度显示的安装函数
    return Install-WithProgress -SoftwareId $id -SoftwareName $name -TimeoutSeconds 600
}

# 主执行逻辑
try {
    # 读取配置
    Write-Host "📋 读取内置配置..." -ForegroundColor Yellow
    
    # 直接使用内置配置
    $yamlContent = $DefaultConfig
    
    # 解析配置
    $softwareList = Parse-YamlConfig -YamlContent $yamlContent
    $totalSoftware = $softwareList.Count
    
    if ($totalSoftware -eq 0) {
        Write-Host "❌ 未找到有效的软件配置" -ForegroundColor Red
        pause
        exit 1
    }
    
    Write-Host "🎯 找到 $totalSoftware 个软件待处理" -ForegroundColor Green
    Write-Host "⏱️  每个软件安装超时时间: 10分钟" -ForegroundColor Cyan
    Write-Host "💡 如果安装卡住，可以按 Ctrl+C 中断当前安装" -ForegroundColor Yellow
    
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
        
        Write-Host "`n💡 失败可能原因:" -ForegroundColor Yellow
        Write-Host "   - 网络连接问题" -ForegroundColor White
        Write-Host "   - 软件包不存在或版本不兼容" -ForegroundColor White
        Write-Host "   - 系统权限不足" -ForegroundColor White
        Write-Host "   - 安装包损坏" -ForegroundColor White
    }
    
    Write-Host "`n💡 提示:" -ForegroundColor Yellow
    Write-Host "   修改脚本内的 `$DefaultConfig` 变量可以自定义软件列表" -ForegroundColor White
    
} catch {
    Write-Host "❌ 脚本执行出错: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "详细错误: $($_.ScriptStackTrace)" -ForegroundColor Red
}

Write-Host "`n✨ 脚本执行完毕" -ForegroundColor Cyan
pause