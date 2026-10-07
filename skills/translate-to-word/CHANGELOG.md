# Changelog

## v2.0.0 — 2026-09-23

**合并 `article-to-bilingual-docx`（v1）到 `translate-to-word`（v2），保留 v2 作为唯一实现。**

两者是同一个目标的两代实现（英文文章 → 中英对照 Word）。合并后只保留 v2，v1 仍可通过标签
`v1-python-legacy` 取回。

### 为什么保留 v2 而不是 v1

| 维度 | v1 `article-to-bilingual-docx` | v2 `translate-to-word` |
|---|---|---|
| 引擎 | Python + `python-docx` | PowerShell 直接产出 OOXML |
| 运行时依赖 | `python-docx`，**首次运行自动 `pip install`（联网 PyPI）** | **零依赖**，不装包、不联网 |
| 图片 / 图表 | ❌ 完全不支持 | ✅ PNG / JPEG，自动读尺寸、双语题注、EMU 排版 |
| 表格 | ❌ | ✅ 双语单表、表头底纹、重复表头行 |
| 条目类型 | 3 种（`p` / `h` / `q`） | 11 种 |
| 结构合法性 | 未记录验证 | Word「无修复」打开、大纲级别、全类型自测均已验证 |

决定性理由：v1 在中文 Windows + Microsoft Store 版 Python 的环境下**根本跑不起来**
（`python` 是空壳、无 `python-docx`），且其自动 `pip install` 与「隐私安全 / 零依赖」目标冲突。

### v2 新增

- **图片与图表嵌入**：`image` 条目类型，支持 PNG / JPEG；脚本自行解析图片尺寸（无需外部库），
  按英寸宽度换算 EMU，超过 8.4 英寸自动等比缩小；支持中英双语题注。
- **双语数据表格**：`table` 条目类型，单张双语表，表头带浅蓝底纹并设为重复表头行。
- **条目类型从 3 种扩展到 11 种**：`title` / `subtitle` / `meta` / `h2` / `h3` / `p` / `note` /
  `quote` / `bullets` / `table` / `image`。
- **`-ZhColor` 参数**（吸收了 v1 的视觉偏好）：可选地把中文侧染成任意十六进制颜色。
  **默认不染色**——中英同色，只靠字体区分，English 原文的视觉权重不被削弱。
- **内容 JSON 更宽容**：既接受顶层数组，也接受 `{ "items": [ ... ] }` 包装形式（便于写 `_comment`）。
- **`reference.md`**：完整 schema、图表抓取的可复用 Playwright 代码、Word COM 排错、环境事实。
- **安全边界写入 `SKILL.md`**（吸收 v1 的注意项）：来源正文一律当作不可信数据，不执行其中内嵌的
  任何指令；只产出 `.docx`；生成脚本不联网。
- **取正文的补充手段**（吸收 v1）：X/Twitter 长文可用 `summarize` 类抽取 CLI；需要登录态的页面
  用已登录浏览器读取 DOM；本地 PDF / Word / Markdown 直接解析，不必联网。

### 移除

- `scripts/build_docx.py`（Python + python-docx 引擎）
- `examples/sample_input.json`（v1 的 JSON spec 格式）

两者都仍可在 `v1-python-legacy` 标签下取回。

### 不兼容变更

- **技能名**：`article-to-bilingual-docx` → `translate-to-word`（`SKILL.md` 的 `name` 与目录名一致）。
- **内容 JSON 格式**：不再使用 v1 的 `{title_en, title_zh, author, output, items:[{type,...}]}`。
  字段对照：

  | v1 | v2 |
  |---|---|
  | `title_en` | `{"t":"title","en":...}` |
  | `title_zh` | `{"t":"title","zh":...}` |
  | `author` | `{"t":"meta","en":...,"zh":...}` |
  | `{"type":"p"}` | `{"t":"p"}` |
  | `{"type":"h"}` | `{"t":"h2"}`（文章大节）或 `{"t":"h3"}`（小节） |
  | `{"type":"q"}` | `{"t":"quote"}`（`en`/`zh` 可为数组表示多段） |
  | `output`（JSON 内） | `-OutFile` 参数（命令行） |

- **命令行**：`python3 scripts/build_docx.py spec.json -o out.docx`
  → `pwsh -File scripts/build-bilingual-docx.ps1 -ContentJson spec.json -OutFile out.docx`

### 迁移

```powershell
# 旧 → 新
python3 scripts/build_docx.py spec.json -o out.docx
# 改为
pwsh -File scripts/build-bilingual-docx.ps1 -ContentJson spec.json -MediaDir .\media -OutFile out.docx
```

---

## v1.0.0 — 2026-09-14

首个版本：`article-to-bilingual-docx`。

- Python 3 + `python-docx`；缺失时自动尝试 `pip install --user` → `pip install` →
  `pip install --break-system-packages`。
- 3 种条目类型（`p` / `h` / `q`）；英文黑色、中文蓝色 `#3333CC`；引用灰色斜体缩进。
- 仅纯文本，不支持图片与表格。