$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd().Trim()
if ($raw) { $data = $raw | ConvertFrom-Json }

$cwd = $data.workspace.current_dir

# ANSI escapes
$e = [char]27
$cyan   = "$e[36m"; $green = "$e[32m"; $yellow = "$e[33m"
$red    = "$e[31m"; $gray  = "$e[90m"; $reset = "$e[0m"

$parts = @()

# model + effort
$modelName = if ($data.model.display_name) { $data.model.display_name } else { "deepseek" }
$effort = if ($env:CLAUDE_CODE_EFFORT_LEVEL) { $env:CLAUDE_CODE_EFFORT_LEVEL } else { "?" }
$parts += "$cyan$modelName$reset[$effort]"

# context window
$ctx = $data.context_window
if ($ctx -and $null -ne $ctx.used_percentage) {
    $pct = [math]::Round($ctx.used_percentage, 0)
    $total = $ctx.context_window_size
    if ($total -and $total -gt 0) {
        $totalK = [math]::Round($total / 1000, 0)
        $usedK = [math]::Round($pct / 100.0 * $totalK, 0)
    } else { $totalK = 0; $usedK = 0 }

    $barLen = 10
    $filled = [math]::Round($pct / 100.0 * $barLen, 0)
    $filled = [math]::Max(0, [math]::Min($barLen, $filled))
    $empty = $barLen - $filled

    if ($pct -ge 80)      { $barColor = $red }
    elseif ($pct -ge 60)  { $barColor = $yellow }
    else                  { $barColor = $green }

    $bar = "$barColor$([string][char]0x2588 * $filled)$reset$([string][char]0x2591 * $empty)"
    $parts += "ctx:[$bar]"
}

# input/output tokens
$totalIn  = if ($ctx -and $null -ne $ctx.total_input_tokens)  { $ctx.total_input_tokens }  else { $null }
$totalOut = if ($ctx -and $null -ne $ctx.total_output_tokens) { $ctx.total_output_tokens } else { $null }

$tok = @()
if ($null -ne $totalIn) {
    $v = if ($totalIn -ge 1000) { "$([math]::Round($totalIn/1000, 1))k" } else { "$totalIn" }
    $tok += "$([char]0x2193)$v"
}
if ($null -ne $totalOut) {
    $v = if ($totalOut -ge 1000) { "$([math]::Round($totalOut/1000, 1))k" } else { "$totalOut" }
    $tok += "$([char]0x2191)$v"
}
if ($null -ne $totalIn -and $null -ne $totalOut) {
    $estCost = $totalIn / 1000000 * 0.28 + $totalOut / 1000000 * 1.10
    if ($estCost -lt 0.005) { $tok += "`$<0.01" }
    else { $tok += "`$$([math]::Round($estCost, 2).ToString('0.00'))" }
}
if ($tok.Count -gt 0) { $parts += ($tok -join " ") }

# DeepSeek balance — 5 min cache
$dsKey = $env:ANTHROPIC_AUTH_TOKEN
$cacheFile = "$env:TEMP\ds_bal.txt"
$bal = $null
if (Test-Path $cacheFile) {
    $age = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
    if ($age.TotalMinutes -lt 4.9) { $bal = Get-Content $cacheFile }
}
if (-not $bal) {
    try {
        $hdr = @{ Authorization = "Bearer $dsKey"; Accept = "application/json" }
        $resp = Invoke-RestMethod -Uri "https://api.deepseek.com/user/balance" -Headers $hdr -TimeoutSec 5
        $bal = [math]::Round([double]$resp.balance_infos[0].total_balance, 2)
        "$bal" | Out-File $cacheFile -Encoding utf8
    } catch { $bal = "--" }
}
$parts += "DS:$([char]0xA5)$bal"

Write-Output "${cwd}`n$($parts -join "  ")"
