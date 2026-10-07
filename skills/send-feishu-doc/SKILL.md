---
name: send-feishu-doc
description: Create a Feishu/Lark document from a summary, article notes, web page digest, report, or Markdown content, then send the document link through Feishu IM. Use from Codex, Cursor, Claude Code, or another Agent Skills client when the user asks to "send as Feishu doc", "create a Feishu document link", "总结文章后发飞书文档", "做成飞书文档发我", or similar workflows.
platforms: [windows, macos]
does:
  - 把 Markdown 内容创建为飞书文档并设置可见权限
  - 把文档链接发送到用户配置的飞书群
boundary: 依赖本机 lark-cli 与用户目录下的配置文件；skill 内不硬编码任何个人 ID、群名或密钥
---

# Send Feishu Doc

把一段 Markdown 内容做成飞书文档、设置可见权限,并把链接发到配置指定的飞书群。

本 skill 的所有目标(接收群、发送身份、profile、lark-cli 路径)均来自用户配置,不在 skill 内硬编码任何个人 ID、群名或路径。

## 0. 读取配置(必须先做)

配置文件为各自平台的用户目录下约定路径:

| 平台 | 配置文件路径 |
|---|---|
| macOS / Linux | `~/.config/feishu-skills/config.json` |
| Windows | `%USERPROFILE%\.config\feishu-skills\config.json`(即 `C:\Users\<你的用户名>\.config\feishu-skills\config.json`) |

读取示例:

```bash
cat ~/.config/feishu-skills/config.json                                 # macOS / Linux
```

```powershell
Get-Content "$env:USERPROFILE\.config\feishu-skills\config.json"        # Windows PowerShell
```

字段说明:

| 字段 | 是否必填 | 作用 |
|---|---|---|
| `chat_id` | 必填 | 接收文档链接的飞书群 ID |
| `chat_name` | 可选 | 群名,仅作为给用户看的可读标签,不可用于按名字解析群 |
| `sender_identity` | 必填 | 发消息身份:`bot` 或 `user` |
| `profile` | 可选 | 指定 lark-cli profile 名;为空则使用当前默认 identity |
| `lark_cli_path` | 可选 | lark-cli 不在 PATH 时的手动路径 |
| `message_format` | 可选 | `link`(默认,只发标题+链接)或 `link_with_excerpt`(附带 2–3 句正文摘要) |

所有 `lark-cli` 调用在 `profile` 非空时都要带上 `--profile "<profile>"`;为空则省略该参数。

如果配置文件不存在,提示用户运行项目自带的 `scripts/setup.sh`(Windows: `scripts\setup.ps1`)引导生成,然后停止,不要猜测任何 ID。

## 1. 定位 lark-cli

按顺序解析,取第一个可用者:

```bash
if command -v lark-cli >/dev/null 2>&1; then
  LARK_BIN="$(command -v lark-cli)"
else
  LARK_BIN="$(jq -r '.lark_cli_path // empty' ~/.config/feishu-skills/config.json)"
fi
test -n "$LARK_BIN" || echo "lark-cli not found, install with: npm install -g @larksuite/cli"
```

安装方式:`npm install -g @larksuite/cli`(`lark-cli update` 可自动检测并更新)。下面的命令示例统一写作 `lark-cli`,实际执行时若解析到非标准路径,换成 `$LARK_BIN`。

## 2. 工作流

1. 准备内容为简洁 Markdown。
   - 标题要明确。
   - 若是文章/新闻摘要,保留来源链接。
   - 除非内容过长或 CLI 需要 `@file`,否则不要创建本地文件。
2. 检查登录:`lark-cli auth status`。
   - 创建文档和设置权限需要用户身份(`--as user`);群发送用配置里的 `sender_identity`。
   - 仅在用户明确要求私发/直发时,才用当前用户的 `openId` 替代配置的群。
   - 前置条件:应用 bot 必须是目标群成员。若 `im +chat-members-list --as bot` 或发送返回 `232011`(操作者不在群里),先把 bot 加进群,不要回退用 `--as user` 发这个配置的群。
   - 若用户身份缺少文档/权限 scope,只申请 CLI 提示的那一个 scope/domain,并在 CLI 要求用户授权时展示验证 URL/二维码。bot 的发送权限在开放平台后台配置,不走 `auth login`。
3. 创建文档:
   - 默认创建位置是用户 Drive 根目录;除非用户要求,不使用 wiki 或团队文件夹。
   - **Windows 编码与路径特别规范（极其重要）**：
     - **严禁**直接使用 PowerShell 管道（`Get-Content ... | lark-cli ... --content -`），因为 Windows PowerShell 管道默认使用 ASCII 编码，会导致所有中文字符全部损坏变为问号 `?` 乱码！
     - 必须将内容写入 UTF-8 临时文件，并通过 `--content @<路径>` 方式读取。
     - 临时文件应保存在用户目录（如 `$env:TEMP` 或 `C:\Users\<用户名>\`），**严禁**放在包含 `d:\dev` 等带 `/dev` 字符串的开发目录下，否则会被 `lark-cli` 误判为 Linux `/dev` 设备系统保护目录而拒绝读取。任务结束后删除临时文件。
4. 设置新文档链接权限。
   - **默认权限**：统一设置为**所有人/互联网人都能访问（任何人可读）**，即 `external_access=true` + `link_share_entity=anyone_readable`，除非用户明确要求私有或仅租户可读。
   - 用 `docs +create` 返回的 `document_id` 作为 docx token,分两次 patch(飞书可能拒绝同一请求里同时改 `external_access` 和 `link_share_entity`):
     1. `lark-cli drive permission.public patch --as user --token "<document_id>" --type docx --data '{"external_access":true}' --yes --format json`
     2. `lark-cli drive permission.public patch --as user --token "<document_id>" --type docx --data '{"link_share_entity":"anyone_readable"}' --yes --format json`
   - 仅在用户明确要求受限/私有时改为:`{"external_access":false}` 和 `{"link_share_entity":"tenant_readable"}`。
   - 有读权限 scope 时用 `lark-cli drive permission.public get --as user --token "<document_id>" --type docx --format json` 读回,确认两个字段;缺读 scope 时不要阻塞发送,报告 patch 成功、校验需 `docs:permission.setting:read`。
   - 本条即用户对本 skill 创建文档的明确授权;不得用它去改与任务无关的既有链接或批量治理用户提供的文档。
   - 若因缺 scope 导致 patch 失败,只申请 CLI 提示的最小 scope(通常是 `docs:permission.setting:write_only` 或相关 Drive 权限)。
5. 提取并校验文档链接:用 `docs +create` 返回的 URL;结果有歧义时用 `lark-cli drive +inspect --as user --url "<url>" --format json` 核对。
6. 发送链接:
   - 目标为配置的 `chat_id`。群名仅供参考,不要按名字解析接收者。
   - 按配置身份发送:
     ```bash
     LARK_CLI_NO_PROXY=1 lark-cli im +messages-send --as "<sender_identity>" --chat-id "<chat_id>" --text "<title>: <url>" --idempotency-key "<stable-key>" --format json
     ```
   - `message_format=link_with_excerpt` 时,`--text` 改为 `<标题>\n<摘要 2–3 句>\n<url>`。
   - 发送失败 `232011`:先把 bot 加进群(`im chat.members create --as user --chat-id <id> --member-id-type app_id` 用 app id,或在群机器人设置里添加),不要对该配置群改用 `--as user` 重试。
   - 用户明确要私发/直发时,改用 `--as user --user-id "<open_id>"`。
   - 幂等键包含任务名/日期,避免重试重复发送。

## 3. 默认值

- 接收群:配置的 `chat_id`;没有配置时执行 `scripts/setup.sh`。
- 发送身份:配置的 `sender_identity`(默认 `bot`);创建文档与设置权限恒为 `--as user`。
- 可见性:公开来源 → 任何人可读;涉密/受限来源 → 私有或仅租户可读,除非明确授权公开。
- 目的地:Drive 根目录。
- 消息格式:`link` 或 `link_with_excerpt`,见配置。
- 语言:跟随用户请求的输出语言;中文提问默认中文。

## 4. 安全

- 永不把 app 密钥、access token、refresh token、OAuth code 写进 skill 文件或打印。
- `lark-cli` 报告使用代理时,仅在影响用户安全预期时提及。
- 除非用户明确要求公开编辑,不做 `anyone_editable`。
- 用户提供的既有链接:权限变更属高风险,遵循 lark-drive 权限流程;默认 `anyone_readable` patch 只适用于本 skill 新建的文档。
- 需要授权时只申请 CLI 提示缺失的最小 scope,如 `im:message.send_as_user`、`docx:document:create` 或相关 Drive scope。

## 5. 验收标准

- 用给定内容创建了飞书文档。
- 公开来源:新建文档设置为任何人可读;读回确认 `external_access=true` 与 `link_share_entity=anyone_readable`(有读 scope 时)。
- 受限来源:未经用户明确授权不公开。
- 文档链接已按配置身份(`--as bot` 或 `--as user`)发送到配置的 `chat_id`。
- 最终回复包含文档 URL 与飞书消息 ID(有则带上)。