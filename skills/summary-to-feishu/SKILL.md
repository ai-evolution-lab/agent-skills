---
name: summary-to-feishu
description: 端到端编排 skill——把来源(URL、网页、PDF、音视频、本地文件)做详细总结,并做成飞书文档、设置权限、把链接发到配置的飞书群。触发词包括：总结并发飞书、总结并发送、总结发到群里、详细总结发飞书、把这篇总结发到文档群。本 skill 只负责编排,总结与发送分别委托 summary 与 send-feishu-doc。
platforms: [windows, macos]
does:
  - 编排「详细总结 → 飞书文档 → 发链接」一条龙流程
  - 防止重复文档与重复消息
boundary: 纯编排层，必须与 summary、send-feishu-doc 同装才可用；自身不生产内容
---

# Summary to Feishu

「详细总结 → 飞书文档 → 发送链接」的一条龙入口。本 skill 不复制 `summary` 与 `send-feishu-doc` 的实现,只负责编排顺序、参数衔接与双重发送(重复文档/重复消息)的防护。

## 职责边界

- 内容生产 → 委托 `summary` skill(遵循其输入路由、原始来源阅读门与详细输出契约)。
- 飞书交付 → 委托 `send-feishu-doc` skill(遵循其创建/权限/发送工作流)。
- 本 skill 只做:确认输入、判定来源公开性、串起两步、返回结果。

## 工作流

1. **确认输入与配置**
   - 确定来源(URL、本地文件路径或用户粘贴的长文)。
   - 读取配置文件:`~/.config/feishu-skills/config.json`(macOS/Linux)或 `%USERPROFILE%\.config\feishu-skills\config.json`(Windows);若缺失,提示运行 `scripts/setup.sh`(Windows: `scripts\setup.ps1`),不要猜测群 ID。

2. **详细总结(委托 summary)**
   - 调用 `summary` skill,按其「原始来源阅读门」校验确实读到原文;需登录的来源走登录态浏览器。
   - 用详细模式产出:执行 `summarize "<input>" --length long --prompt-file "<summary skill 基目录>/reference/rich-summary-prompt.md"`,音视频追加 `--timestamps`;模板不可用时退化为 summary skill 内嵌的 10 段契约。
   - 校验:exit 0、总结非空、10 段结构完整、来源 URL 与提取路径已记录。

3. **权限设置**
   - 默认权限：所有生成的飞书文档默认设置为**所有人/互联网人都能访问（任何人可读）**，即 `external_access=true` 与 `link_share_entity=anyone_readable`。
   - 仅当用户明确要求「保持私有」或「仅租户可读」时，才设置为受限权限。

4. **交付(委托 send-feishu-doc)**
   - 把上一步产出的 Markdown 总结作为内容,调用 `send-feishu-doc` skill 按其工作流:创建文档 → 分两步设权限 → 校验链接 → 按配置身份发送到配置的 `chat_id`。
   - 保留来源链接在文档正文中。
   - Windows 环境特别注意：避免直接用 PowerShell 管道传递 Markdown 导致编码被转为 ASCII 问号乱码；应使用临时文件 `@file` 传入，且路径避免包含 `/dev` 等保留前缀。
   - 注意:`summary` 默认不发送、`send-feishu-doc` 只被本 skill 调用一次,全程只有一条飞书消息;若发现任一环节可能重复发送,停下来。

5. **返回结果**
   - 给用户:总结(简版或全文)、飞书文档 URL、消息 ID(有则带)、来源 URL 与提取路径。

## 不要做什么

- 不要私自修改未授权的既有飞书文档权限。
- 不要用 `--as user` 代替 bot 发送配置的群;bot 不在群时报 `232011`,先把 bot 加入群。
- 不申请多余 scope,只按 CLI 提示的最小 scope 授权。

## 验收标准

- 来源已被详细总结(10 段契约)。
- 飞书文档已创建并设置正确可见性。
- 链接已发送到配置的 `chat_id`,且只发了一条。
- 回复含文档 URL 与消息 ID(有则带)。