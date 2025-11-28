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

# 改进的安装函数 - 双重验证安装状态
function Install-WithProgress {
    param(
        [string]$SoftwareId,
        [string]$SoftwareName,
        [string[]]$UninstallNames,
        [int]$TimeoutSeconds = 300
    )
    
    Write-Host "📥 开始安装: $SoftwareName..." -ForegroundColor Green
    
    try {
        # 启动安装进程
        $process = Start-Process -FilePath "winget" -ArgumentList @(
            "install", "--id", $SoftwareId, "--source", "winget", "--silent",
            "--disable-interactivity", "--accept-package-agreements", "--accept-source-agreements"
        ) -PassThru -NoNewWindow
        
        # 显示进度动画
        $startTime = Get-Date
        $dots = 0
        $maxDots = 3
        $phase = 1  # 1=下载, 2=安装
        
        Write-Host "🌐 开始下载..." -ForegroundColor Cyan
        
        while (-not $process.HasExited -and ((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
            $dots = ($dots + 1) % ($maxDots + 1)
            $progress = "." * $dots + " " * ($maxDots - $dots)
            
            # 根据时间切换阶段提示
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
        
        if (-not $process.HasExited) {
            # 超时处理
            Write-Host "⏰ $SoftwareName 安装超时，强制终止..." -ForegroundColor Red
            $process.Kill()
            Start-Sleep -Seconds 2
            return $false
        } else {
            # 获取退出代码
            $exitCode = $process.ExitCode
            
            # 双重验证：检查退出代码 + 实际验证软件是否安装成功
            $actuallyInstalled = Test-SoftwareInstalled -SoftwareId $SoftwareId -UninstallNames $UninstallNames
            
            if ($exitCode -eq 0 -or $actuallyInstalled) {
                # 安装成功（通过退出代码或实际验证）
                if ($exitCode -ne 0 -and $actuallyInstalled) {
                    Write-Host "⚠️  Winget 报告失败但软件已安装成功（常见于系统组件如 OneDrive）" -ForegroundColor Yellow
                }
                Write-Host "✅ $SoftwareName 安装成功" -ForegroundColor Green
                return $true
            } else {
                # 安装失败
                Write-Host "❌ $SoftwareName 安装失败，退出代码: $exitCode" -ForegroundColor Red
                
                # 根据退出代码提供更多信息
                switch ($exitCode) {
                    0x8A150011 { 
                        Write-Host "💡 提示: 软件可能已安装或存在冲突" -ForegroundColor Yellow
                    }
                    0x8A150004 { 
                        Write-Host "💡 提示: 找不到指定的软件包" -ForegroundColor Yellow
                    }
                    0x8A150007 { 
                        Write-Host "💡 提示: 安装被用户取消" -ForegroundColor Yellow
                    }
                    default { 
                        Write-Host "💡 提示: 请检查网络连接和系统权限" -ForegroundColor Yellow
                    }
                }
                
                return $false
            }
        }
        
    } catch {
        Write-Host "❌ $SoftwareName 安装异常: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "💡 解决方案: 尝试手动安装或检查系统环境" -ForegroundColor Yellow
        
        # 即使有异常，也检查是否实际安装成功
        $actuallyInstalled = Test-SoftwareInstalled -SoftwareId $SoftwareId -UninstallNames $UninstallNames
        if ($actuallyInstalled) {
            Write-Host "✅ $SoftwareName 实际上已安装成功" -ForegroundColor Green
            return $true
        }
        
        return $false
    }
}

# 检查软件是否已安装
function Test-SoftwareInstalled {
    param(
        [string]$SoftwareId,
        [string[]]$UninstallNames
    )
    
    # 方法1: 通过 Winget 检查
    try {
        $null = winget list --id $SoftwareId --exact -s winget 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
    } catch {
        # 忽略检查错误
    }
    
    # 方法2: 通过注册表检查
    if ($UninstallNames) {
        foreach ($uninstallName in $UninstallNames) {
            try {
                $uninstallPaths = @(
                    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                )
                
                foreach ($path in $uninstallPaths) {
                    $items = Get-ItemProperty $path -ErrorAction SilentlyContinue | 
                             Where-Object { $_.DisplayName -like "*$uninstallName*" }
                    if ($items) {
                        return $true
                    }
                }
            } catch {
                # 静默处理错误
            }
        }
    }
    
    # 方法3: 检查特定系统组件（如 OneDrive）
    if ($SoftwareId -eq "Microsoft.OneDrive") {
        # OneDrive 是系统组件，检查其可执行文件是否存在
        $oneDrivePaths = @(
            "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
            "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
            "$env:ProgramFiles(x86)\Microsoft OneDrive\OneDrive.exe"
        )
        
        foreach ($path in $oneDrivePaths) {
            if (Test-Path $path) {
                return $true
            }
        }
    }
    
    return $false
}

# 卸载软件
function Uninstall-Software {
    param(
        [string]$SoftwareId,
        [string]$SoftwareName,
        [string[]]$UninstallNames
    )
    
    Write-Host "🗑️  正在卸载: $SoftwareName..." -ForegroundColor Magenta
    
    $uninstalled = $false
    
    # 方法1: 通过 Winget 卸载
    if ($SoftwareId) {
        try {
            winget uninstall --id $SoftwareId --exact -s winget --silent
            Write-Host "✅  Winget 卸载完成" -ForegroundColor Green
            $uninstalled = $true
            Start-Sleep -Seconds 2
        } catch {
            Write-Host "⚠️  Winget 卸载失败，尝试其他方法..." -ForegroundColor Yellow
        }
    }
    
    # 方法2: 通过控制面板卸载
    if ($UninstallNames -and -not $uninstalled) {
        foreach ($uninstallName in $UninstallNames) {
            try {
                # 查找卸载命令
                $uninstallPaths = @(
                    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                )
                
                foreach ($path in $uninstallPaths) {
                    $items = Get-ItemProperty $path -ErrorAction SilentlyContinue | 
                             Where-Object { $_.DisplayName -like "*$uninstallName*" }
                    
                    foreach ($item in $items) {
                        if ($item.UninstallString) {
                            Write-Host "🔧 执行卸载命令..." -ForegroundColor Cyan
                            $uninstallString = $item.UninstallString
                            
                            # 处理常见的卸载命令格式
                            if ($uninstallString -match '^"([^"]+)"') {
                                $uninstallExe = $matches[1]
                                $uninstallArgs = $uninstallString.Substring($matches[0].Length)
                                Start-Process -FilePath $uninstallExe -ArgumentList "$uninstallArgs /S" -Wait
                            } else {
                                Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstallString /S`"" -Wait
                            }
                            
                            $uninstalled = $true
                            Start-Sleep -Seconds 3
                        }
                    }
                }
            } catch {
                Write-Host "⚠️  控制面板卸载失败: $uninstallName" -ForegroundColor Red
            }
        }
    }
    
    return $uninstalled
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
    Write-Host "🔍 软件ID: $id" -ForegroundColor Gray
    
    # 检查是否已安装
    $isInstalled = Test-SoftwareInstalled -SoftwareId $id -UninstallNames $uninstallNames
    
    # 如果已安装，先卸载
    if ($isInstalled) {
        Write-Host "⚠️  检测到已安装，执行卸载..." -ForegroundColor Magenta
        Uninstall-Software -SoftwareId $id -SoftwareName $name -UninstallNames $uninstallNames
    } else {
        Write-Host "🆕 软件未安装，直接安装..." -ForegroundColor Cyan
    }
    
    # 使用改进的安装函数（传入 UninstallNames 用于双重验证）
    return Install-WithProgress -SoftwareId $id -SoftwareName $name -UninstallNames $uninstallNames -TimeoutSeconds 300
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
    Write-Host "⏱️  每个软件安装超时时间: 5分钟" -ForegroundColor Cyan
    Write-Host "💡 如果安装卡住，可以按 Ctrl+C 中断当前安装" -ForegroundColor Yellow
    Write-Host "💡 注意: 某些系统组件（如 OneDrive）可能报告失败但实际安装成功" -ForegroundColor Yellow
    
    # 按顺序处理每个软件
    $successCount = 0
    $failedList = @()
    
    for ($i = 0; $i -lt $totalSoftware; $i++) {
        $software = $softwareList[$i]
        
        try {
            $result = Process-Software -Software $software -Index ($i + 1) -Total $totalSoftware
            
            if ($result) {
                $successCount++
                Write-Host "✅ 进度: $successCount/$totalSoftware 完成" -ForegroundColor Green
            } else {
                $failedList += $software.name
                Write-Host "❌ 进度: $successCount/$totalSoftware 完成" -ForegroundColor Red
            }
        } catch {
            Write-Host "❌ 处理 $($software.name) 时发生异常: $($_.Exception.Message)" -ForegroundColor Red
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
        Write-Host "`n💡 解决方案:" -ForegroundColor Yellow
        Write-Host "   - 检查网络连接后重试" -ForegroundColor White
        Write-Host "   - 手动安装失败的软件" -ForegroundColor White
        Write-Host "   - 确保以管理员身份运行脚本" -ForegroundColor White
    } else {
        Write-Host "🎊 所有软件安装成功！" -ForegroundColor Green
    }
    
    Write-Host "`n💡 提示:" -ForegroundColor Yellow
    Write-Host "   修改脚本内的 `$DefaultConfig` 变量可以自定义软件列表" -ForegroundColor White
    
} catch {
    Write-Host "❌ 脚本执行出错: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "详细错误: $($_.ScriptStackTrace)" -ForegroundColor Red
}

Write-Host "`n✨ 脚本执行完毕" -ForegroundColor Cyan
pause