# litlab-ops

literature-lab 部署运维工具集 — 把每日文献流水线搬到不关机 Windows 机器上。

## 文件

| 文件 | 用途 |
|------|------|
| `scripts/setup-target-machine.ps1` | 目标机一键部署：装 CC → 配 DeepSeek → cloneliterature-lab → 设定时任务 |
| `scripts/deepseek-balance.ps1` | CC statusLine HUD，底部状态栏显示 DeepSeek 余额和上下文用量 |

## 用法

目标机上（需先装 Node.js）：

```powershell
git clone https://github.com/TensorSpicyJ/litlab-ops D:\playground\litlab-ops
Get-Content D:\playground\litlab-ops\scripts\setup-target-machine.ps1 -Raw -Encoding UTF8 | Invoke-Expression
```

statusLine 配置（部署脚本已自动写入，这里只是手动参考）：

```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -File D:\\playground\\litlab-ops\\scripts\\deepseek-balance.ps1"
}
```
