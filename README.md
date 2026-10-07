# agent-skills

跨设备（Windows / macOS）同步个人 **Agent Skills** 与全局 `AGENTS.md` 的单仓库方案。
一个 GitHub 仓库是真源；每台设备**选装**需要的 skill；日常在**浏览器可视化页面**里安装、卸载、同步、回推。

兼容 Codex、Claude Code、Cursor、opencode、OpenClaw、DeepSeek Harness 等所有遵循 `skills/<name>/SKILL.md` 目录约定的工具——部署方式只是给各工具的 skills 目录建链接，不复制文件。

## 一键引导（每台设备只做一次，之后全在浏览器）

**Windows（PowerShell 7）**
```powershell
irm https://raw.githubusercontent.com/ai-evolution-lab/agent-skills/main/install.ps1 | iex
```

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/ai-evolution-lab/agent-skills/main/install.sh | bash
```

要求：`git` + `node`（脚本会检查并给出安装指引）。引导做三件事：clone 仓库到 `~/.agents/agent-skills`、注册 `skills` 命令、跑 `skills init`。

## 日常管理

```
skills dashboard        ✨ 打开可视化页面（127.0.0.1 本地服务，随机端口+token）
                        全量 skill 卡片：作用列表、范围边界、平台徽章
                        实时检测本机已装/未装；多选勾选 → 批量安装/卸载
                        顶栏按钮：同步 / 回推 / 体检修复；命令输出可展开查看
```

终端命令（与页面同一套核心，供脚本化/SSH 场景）：

| 命令 | 作用 |
|---|---|
| `skills list` | 仓库全量 + 本机 ✔/✘ 状态、未装清单 |
| `skills info <name>` | 单个 skill 的作用 / 边界 / 平台 |
| `skills add <name...>` 或 `--all` | 安装（建链接；真实目录自动备份接管） |
| `skills remove <name...>` | 卸载（只删链接，不动仓库文件） |
| `skills sync` | `git pull --ff-only` + 重链已装 + AGENTS.md 同步 + 新 skill 提示 |
| `skills push [msg]` | 本地改动回推（自动重生成 catalog） |
| `skills doctor [--fix]` | 链接体检 / 修复 |
| `skills status --json` | 机器可读状态 |

## 链接部署模型

- 仓库位于 `~/.agents/agent-skills`，**每台设备的选装记录**在 `~/.agents/skills.lock.json`（不进仓库）。
- Windows：优先放入聚合 hub `~/.skills`（junction，免管理员权限）；macOS/Linux：放入每个**已存在**的工具目录（`~/.claude/skills`、`~/.codex/skills`、`~/.agents/skills`、`~/.cursor/skills`、`~/.config/opencode/skills`、`~/.openclaw/workspace/skills`），符号链接，realpath 去重。
- skill frontmatter 的 `platforms` 不含当前系统时默认不装、页面置灰（`add` 可强制）。

## 每个 skill 的元数据约定（写在 SKILL.md frontmatter）

```yaml
---
name: xxx
description: 给模型看的触发描述（含触发词）
platforms: [windows, macos]     # 缺省 = 全平台
does:                          # 能做什么（dashboard 卡片列表）
  - …
boundary: 范围与边界，一句话说清不适用场景
---
```

未知字段对各工具无害（它们只读 name/description）。页面与 `skills list/info` 全部从这里解析，**没有第二份清单**。

## 新增一个 skill 的流程

1. `skills/<name>/` 建目录，写 SKILL.md（含上面元数据）；
2. `skills add <name>` 本机先装上测；
3. `skills push` —— 自动重生成 `docs/catalog.json` 与 Pages 画廊页；
4. 其他设备 `skills sync`，`skills dashboard` 里会出现"🆕 新 skill"横幅，勾选即装。

## AGENTS.md 同步

仓库 `agents/AGENTS.md` 是全局规则真源。`skills sync` 会：
- 与 `~/.agents/AGENTS.md` 做双向 mtime 比较并拷贝较新一方（DSH/Codex 的符号链接自动吃到）；
- 对 opencode / OpenClaw 各自保留专属内容的 AGENTS.md，只替换 `<!-- BEGIN shared: <id> … END shared: <id> -->` 标记块（沿用现行约定，缺标记只警告不动手）。

## 线上画廊

GitHub Pages（`/docs`）提供只读画廊：所有 skill 的作用与边界，安装按钮 = 复制命令。本机状态属于设备隐私，只存在于本地 `skills dashboard`。

## FAQ

- **pull 冲突？** `sync` 只做 `--ff-only`，分叉时提示手工处理，绝不自动 rebase/覆盖。
- **没装 node？** dashboard 不可用；`git -C ~/.agents/agent-skills pull` 后手动 `skills.mjs`… 需 node，所以请先装。核心命令都依赖 node，这是唯一硬要求。
- **仓库删了某 skill？** sync 报孤儿提示，`skills remove <name>` 清理记录。
- **Windows 旧工具入口**：`.codex/.claude/.cursor/…` 的 skills 目录本身就是指向 hub 的 junction 时，只建一份链接（realpath 去重），不会重复。

## 安全边界

- 本仓库永不收录含密钥/公司内容的 skill；配置文件一律留设备本地。
- dashboard 服务只监听 `127.0.0.1`、随机端口、URL 带随机 token、30 分钟空闲自动退出，Ctrl+C 即关。
