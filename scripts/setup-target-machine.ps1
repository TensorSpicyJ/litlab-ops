# literature-lab — 目标机一键部署
# 用法: 右键 → "使用 PowerShell 运行"，或
#       powershell -ExecutionPolicy Bypass -File setup-target-machine.ps1
param(
    [string]$RunTime = "08:00"
)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "literature-lab Setup"

Write-Host @"
================================================
  literature-lab 目标机部署
  装 CC → 配 DeepSeek → 设定时任务
================================================

"@

# ═══════════════════════════════════════════════
# 1. 检查 Node.js
# ═══════════════════════════════════════════════
Write-Host "[1/7] Checking Node.js..."
$nodeOk = $true
try { $nv = & node --version 2>&1 } catch { $nodeOk = $false }
if (-not $nodeOk -or $LASTEXITCODE -ne 0) {
    Write-Host "Node.js 未安装。请先下载安装: https://nodejs.org (LTS 版)"
    Write-Host "安装完成后重新运行本脚本。"
    Read-Host "按 Enter 退出"
    exit 1
}
Write-Host "  Node.js: $nv"

# ═══════════════════════════════════════════════
# 2. 安装 Claude Code
# ═══════════════════════════════════════════════
Write-Host "[2/7] Installing Claude Code..."
$ccOk = $true
try { $cv = & claude --version 2>&1 } catch { $ccOk = $false }
if (-not $ccOk -or $LASTEXITCODE -ne 0) {
    Write-Host "  正在安装 (npm install -g @anthropic-ai/claude-code)..."
    npm install -g @anthropic-ai/claude-code 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "安装失败，请检查 npm 网络连接后重试。"
        Read-Host "按 Enter 退出"
        exit 1
    }
    Write-Host "  [OK] Claude Code 安装完成"
} else {
    Write-Host "  Claude Code: $cv (已安装)"
}

# 找到 claude.exe 完整路径（Task Scheduler 需要）
$claudeExe = (Get-Command claude -ErrorAction SilentlyContinue).Source
if (-not $claudeExe) {
    $claudeExe = "$env:APPDATA\npm\claude.cmd"
}
Write-Host "  claude 路径: $claudeExe"

# ═══════════════════════════════════════════════
# 3. 配 DeepSeek API Key
# ═══════════════════════════════════════════════
Write-Host "[3/7] Configuring DeepSeek API..."

# 先检查已有的 key
$existingKey = $env:ANTHROPIC_AUTH_TOKEN
if (-not $existingKey) {
    # 尝试从现有 settings.json 读
    $existingSettings = "$env:USERPROFILE\.claude\settings.json"
    if (Test-Path $existingSettings) {
        try {
            $s = Get-Content $existingSettings -Raw | ConvertFrom-Json
            $existingKey = $s.env.ANTHROPIC_AUTH_TOKEN
        } catch {}
    }
}

if ($existingKey) {
    Write-Host "  已有 DeepSeek API key: $($existingKey.Substring(0, [Math]::Min(10, $existingKey.Length)))..."
    $useExisting = Read-Host "  用这个 key? (Y/n)"
    if ($useExisting -eq 'n' -or $useExisting -eq 'N') {
        $existingKey = $null
    }
}

if (-not $existingKey) {
    Write-Host "  请输入 DeepSeek API key (sk-...):"
    $apiKey = Read-Host -Prompt "  API Key"
    if (-not $apiKey -or $apiKey.Length -lt 10) {
        Write-Host "  Key 无效，退出。"
        Read-Host "按 Enter 退出"
        exit 1
    }
    $existingKey = $apiKey
}

# ═══════════════════════════════════════════════
# 4. 写入 CC 配置
# ═══════════════════════════════════════════════
Write-Host "[4/7] Writing CC settings.json..."

$settingsDir = "$env:USERPROFILE\.claude"
$settingsPath = "$settingsDir\settings.json"
New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null

# 如果已有配置文件，先备份
if (Test-Path $settingsPath) {
    Copy-Item $settingsPath "$settingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "  已备份现有 settings.json"
}

$settingsJson = @"
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "$existingKey",
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash[1m]",
    "CLAUDE_CODE_EFFORT_LEVEL": "max",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "API_TIMEOUT_MS": "3000000"
  },
  "permissions": {
    "defaultMode": "bypassPermissions",
    "skipDangerousModePermissionPrompt": true
  }
}
"@
Set-Content -Path $settingsPath -Value $settingsJson -Encoding UTF8
Write-Host "  [OK] settings.json 已写入"

# 测试联通
Write-Host "  测试 CC + DeepSeek 联通..."
$env:ANTHROPIC_AUTH_TOKEN = $existingKey
$env:ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic"
$testResult = & claude -p "回复OK即可，不要多说" --no-session-persistence --output-format text 2>&1
if ($testResult -match "OK") {
    Write-Host "  [OK] CC + DeepSeek 联通正常"
} else {
    Write-Host "  [WARN] 测试未返回 OK，输出: $testResult"
    Write-Host "  脚本继续，但建议手动检查 claude 命令是否正常。"
}

# ═══════════════════════════════════════════════
# 5. 拉取 literature-lab
# ═══════════════════════════════════════════════
Write-Host "[5/7] Setting up literature-lab..."

$repoPath = "D:\playground\literature-lab"

if (Test-Path $repoPath) {
    Write-Host "  目录已存在: $repoPath"
    Write-Host "  跳过 clone"
} else {
    # 检查 git
    $gitOk = $true
    try { & git --version 2>&1 | Out-Null } catch { $gitOk = $false }
    if (-not $gitOk) {
        Write-Host "  Git 未安装，无法自动 clone。请手动操作："
        Write-Host "    1. 安装 Git: https://git-scm.com"
        Write-Host "    2. git clone https://github.com/TensorSpicyJ/literature-lab $repoPath"
        Write-Host "    或从主机器复制 D:\playground\literature-lab 到目标机同路径"
    } else {
        Write-Host "  git clone https://github.com/TensorSpicyJ/literature-lab..."
        New-Item -ItemType Directory -Force -Path "D:\playground" | Out-Null
        git clone https://github.com/TensorSpicyJ/literature-lab $repoPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARN] Clone 失败，请手动操作。"
        } else {
            Write-Host "  [OK] Clone 完成"
        }
    }
}

# ═══════════════════════════════════════════════
# 6. 飞书 Webhook
# ═══════════════════════════════════════════════
Write-Host "[6/7] Configuring Feishu webhook..."

$feishuUrl = $env:FEISHU_WEBHOOK_URL

# 尝试从 .claude-to-im\config.env 读取
if (-not $feishuUrl) {
    $ctiPath = "$env:USERPROFILE\.claude-to-im\config.env"
    if (Test-Path $ctiPath) {
        $match = Select-String -Path $ctiPath -Pattern 'FEISHU_WEBHOOK_URL=(.+)' | Select-Object -First 1
        if ($match) { $feishuUrl = $match.Matches.Groups[1].Value.Trim() }
    }
}

if ($feishuUrl) {
    Write-Host "  已有 webhook: $($feishuUrl.Substring(0, [Math]::Min(30, $feishuUrl.Length)))..."
} else {
    Write-Host "  请输入飞书机器人 webhook URL (或直接 Enter 跳过):"
    $feishuUrl = Read-Host -Prompt "  Webhook URL"
    if ($feishuUrl) {
        [Environment]::SetEnvironmentVariable("FEISHU_WEBHOOK_URL", $feishuUrl, "User")
        $env:FEISHU_WEBHOOK_URL = $feishuUrl
        Write-Host "  [OK] 已保存"
    } else {
        Write-Host "  [SKIP] 未配置 webhook，飞书推送将被跳过"
    }
}

# ═══════════════════════════════════════════════
# 7. 注册 Windows 定时任务
# ═══════════════════════════════════════════════
Write-Host "[7/7] Registering scheduled tasks..."

$weekdayPrompt = '在 literature-lab 项目里（D:\playground\literature-lab），按 config/topics.json 跑 thesis 和 core 线全流程：search → filter → analyze → correlate → deposit。跳过 interest 线。产出落到 D:\BaiduSyncdisk\code\OB_NOTE\MY NOTE\12-每日文献知识库\。结束后更新 state/search-log.json 和 state/pipeline-status.json。最后跑 D:\playground\literature-lab\scripts\feishu-push.ps1 推送日报到飞书。'

$weekendPrompt = '在 literature-lab 项目里（D:\playground\literature-lab），搜拓扑序本周新文献。用 config/topology-topics.json。流程：search → analyze（TEX-first，拉 arXiv TeX 源）→ 更新概念空间。产出：新概念/更新概念卡落到 D:\BaiduSyncdisk\code\OB_NOTE\MY NOTE\14-拓扑序学习库\concepts\，新论文笔记落到 papers\，概念关系更新到 relations/concept-relations.md。按 14-拓扑序学习库 的 formal-kb-rules 标准（公式优先、原子构造、TeX 可追溯）。只处理近 7 天新文献。结束后跑 D:\playground\literature-lab\scripts\feishu-push.ps1 推送日报到飞书。'

# 用 schtasks 注册（比 Register-ScheduledTask 更可靠，不需要管理员权限）
$schtasksArgs = @(
    "/create", "/tn", "literature-lab-weekday",
    "/tr", "cmd /c `"$claudeExe`" -p `"$weekdayPrompt`" --add-dir D:\playground --add-dir `"D:\BaiduSyncdisk\code\OB_NOTE\MY NOTE\12-每日文献知识库`" --permission-mode auto --no-session-persistence",
    "/sc", "WEEKLY",
    "/d", "MON,TUE,WED,THU,FRI",
    "/st", $RunTime,
    "/f"
)

Write-Host "  注册 weekday 任务..."
$result = & schtasks @schtasksArgs 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] literature-lab-weekday (Mon-Fri @ $RunTime)"
} else {
    Write-Host "  [WARN] Weekday 任务注册失败: $result"
}

$schtasksArgs = @(
    "/create", "/tn", "literature-lab-weekend",
    "/tr", "cmd /c `"$claudeExe`" -p `"$weekendPrompt`" --add-dir D:\playground --add-dir `"D:\BaiduSyncdisk\code\OB_NOTE\MY NOTE\12-每日文献知识库`" --add-dir `"D:\BaiduSyncdisk\code\OB_NOTE\MY NOTE\14-拓扑序学习库`" --permission-mode auto --no-session-persistence",
    "/sc", "WEEKLY",
    "/d", "SAT",
    "/st", $RunTime,
    "/f"
)

Write-Host "  注册 weekend 任务..."
$result = & schtasks @schtasksArgs 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] literature-lab-weekend (Saturday @ $RunTime)"
} else {
    Write-Host "  [WARN] Weekend 任务注册失败: $result"
}

# ═══════════════════════════════════════════════
# 完成
# ═══════════════════════════════════════════════
Write-Host @"

================================================
  部署完成!
================================================

定时任务:
  literature-lab-weekday : 周一至五 $RunTime
  literature-lab-weekend : 周六 $RunTime

手动测试:
  claude -p "在 literature-lab 按 topics.json 快速扫一遍 LSCO 新文献，只筛不读" --add-dir D:\playground --permission-mode auto --no-session-persistence

查看状态:
  D:\playground\literature-lab\state\pipeline-status.json

修改运行时间:
  schtasks /change /tn literature-lab-weekday /st 09:30

================================================
"@

Read-Host "按 Enter 退出"
