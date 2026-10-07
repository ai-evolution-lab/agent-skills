# AGENTS.md — 本机通用 agent 规则

> **真源（single source of truth）：`~/.agents/AGENTS.md`**
>
> 本文件供本机所有 agent 工具共享，接入方式分两类：
>
> | 工具 | 全局指令文件 | 接入方式 |
> |---|---|---|
> | DeepSeek Harness | `$DSH_HOME/AGENTS.md`（本机 `DSH_HOME=D:\dev\code\deepseek-harness\dsh-home`，该变量仅在 DSH 进程内生效；另在默认位置 `~/.dsh/AGENTS.md` 留了同样的链接兜底） | 符号链接 → 本文件，改本文件即生效 |
> | Codex | `~/.codex/AGENTS.md` | 符号链接 → 本文件，改本文件即生效 |
> | opencode | `~/.config/opencode/AGENTS.md` | 该文件另有专属内容，采用「标记块同步」 |
> | OpenClaw | `~/.openclaw/workspace/AGENTS.md` | 该文件另有专属内容，采用「标记块同步」 |
>
> 「标记块同步」= 下面 `BEGIN/END shared` 之间是共享内容，与 opencode / OpenClaw 中的同名标记块
> 必须保持逐字一致。改动时以本文件为准，再同步过去。

<!-- BEGIN shared: network-fetch-priority | source: ~/.agents/AGENTS.md | sync: verbatim -->

## 网络请求策略（固定优先级）

任何联网需求，严格按以下顺序降级。**上一级没有明确失败之前，不得跳到下一级。**

### 第 1 级 · Firecrawl（首选，已配置 API key）

> 工具名前缀因 harness 而异（DSH 为 `mcp__firecrawl__*`，opencode 为 `firecrawl_firecrawl_*`），
> 以当前会话实际列出的 Firecrawl 工具为准。

- 搜索网页 / 新闻：`firecrawl_search`
- 抓取指定页面：`firecrawl_scrape`
- 解析本地文档（PDF / Word 等）：`firecrawl_parse`
- 跨站点结构化调研：`firecrawl_agent`

### 第 2 级 · 模型内置搜索与抓取

仅当 Firecrawl 明确报错或不可用时：

- 搜索：`web_search`
- 抓取：`web_fetch`

### 第 3 级 · 浏览器（兜底）

仅当前两级都取不到目标内容时，用真实浏览器渲染后读取正文：

- Playwright：先 `browser_navigate` 打开页面，再取
  `document.querySelector('main')?.innerText ?? document.body.innerText`
- 或直接使用本机 Chrome

适用场景：目标站点对普通抓取返回 403 / 429、正文由 JS 渲染、需要登录态或页面交互。

## 硬性约束

- **禁止**用 `web_fetch` 直接抓搜索引擎结果页（DuckDuckGo / Bing 等常被阻断）。
- 同一级最多重试一次；连续失败立即降级，不要反复重试同一个工具。
- 已经成功取到内容后，不要再调用其他工具重复抓取同一页面。
- 在回答中说明最终用哪一级取得的内容；降级到第 3 级时尤其要说明。

## 已知案例

- `openai.com/index/*`：对普通抓取一律返回 **403**（含 Firecrawl），**所有** `/index/` 页面都如此，
  并非单页特例。直接走第 3 级浏览器访问即可取得完整正文。同类 Cloudflare 站点照此处理。

<!-- END shared: network-fetch-priority -->