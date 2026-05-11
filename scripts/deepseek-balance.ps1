$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
# Line 1: working directory
$raw = ($input | Out-String).Trim()
if ($raw) { $data = $raw | ConvertFrom-Json }

$cwd = $data.workspace.current_dir

# Line 2: model + effort + context + balance
$out = @()

$model = if ($data.model.display_name) { $data.model.display_name } else { "deepseek-v4-pro" }
$effort = $env:CLAUDE_CODE_EFFORT_LEVEL
$out += "${model} [${effort}]"

$ctx = $data.context_window
if ($ctx -and $null -ne $ctx.used_percentage) {
    $pct = [math]::Round($ctx.used_percentage, 0)
    $total = $ctx.context_window_size
    if ($total -and $total -gt 0) {
        $totalK = [math]::Round($total / 1000, 0)
        $usedK = [math]::Round($pct / 100 * $total / 1000, 0)
        $barLen = 10
        $filled = [math]::Round($pct / 100 * $barLen, 0)
        $filled = [math]::Max(0, [math]::Min($barLen, $filled))
        $empty = $barLen - $filled
        $bar = ([string][char]0x2588 * $filled) + ([string][char]0x2591 * $empty)
        $out += "ctx:${pct}% ${usedK}k/${totalK}k [${bar}]"
    } else {
        $out += "ctx:${pct}%"
    }
}

# DeepSeek balance (5min cache)
$key = $env:ANTHROPIC_AUTH_TOKEN
$cache = "$env:TEMP\ds_bal.txt"
$val = $null
if (Test-Path $cache) {
    $age = (Get-Date) - (Get-Item $cache).LastWriteTime
    if ($age.TotalMinutes -lt 4.9) { $val = Get-Content $cache }
}
if (-not $val) {
    try {
        $hdr = @{ "Authorization" = "Bearer $key"; "Accept" = "application/json" }
        $resp = Invoke-RestMethod -Uri "https://api.deepseek.com/user/balance" -Headers $hdr -TimeoutSec 5
        $val = [math]::Round([double]$resp.balance_infos[0].total_balance, 2)
        "$val" | Out-File $cache -Encoding utf8
    } catch { $val = "--" }
}
$out += "DS:$([char]0xA5)${val}"

Write-Output "${cwd}`n$($out -join "  ")"
