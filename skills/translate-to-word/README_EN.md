# translate-to-word

> Turn an article into a **paragraph-aligned bilingual (English + Chinese) Word document** — and embed the article's figures and charts along with it.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Runtime](https://img.shields.io/badge/runtime-PowerShell%207%2B-5391FE.svg)](#requirements)
[![Dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen.svg)](#what-it-does)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg)](#requirements)

This is an **Agent Skill** (not an npm package, not a Python library). You say one sentence to your agent, and it will:

1. Fetch the article body (falling back Firecrawl → built-in search → browser)
2. **Read the whole piece first**, then translate with full-document context instead of sentence-by-sentence
3. Capture the original figures and data charts
4. Produce a properly formatted `.docx`

[中文](README.md) | English

---

## Contents

- [What it does](#what-it-does)
- [What the output looks like](#what-the-output-looks-like)
- [How to download](#how-to-download)
- [How to use](#how-to-use)
- [Fully open source](#fully-open-source)
- [Any model, including local ones](#any-model-including-local-ones)
- [Privacy and security](#privacy-and-security)
- [Requirements](#requirements)
- [Repository layout](#repository-layout)
- [FAQ](#faq)
- [Relationship to the old version](#relationship-to-the-old-version)
- [License](#license)

---

## What it does

| Capability | Detail |
|---|---|
| **Paragraph-level pairing** | Every English paragraph is **immediately followed** by its Chinese translation — not "English half then Chinese half" |
| **Context-aware translation** | The skill requires reading the whole document first and fixing a glossary up front; **sentence-by-sentence translation is explicitly forbidden** |
| **Figures and charts** | Captures the article's hero image and data charts and embeds them with bilingual captions. v1 could not do this at all |
| **11 item types** | Title, subtitle, source line, two heading levels, body, footnote, quote, list, bilingual table, image |
| **Bilingual tables** | A table becomes **one bilingual table** (headers like `Model / 模型`); numeric content reads better than splitting it into two tables |
| **Native Word structure** | Headings use Word's **built-in** heading styles, so the **navigation pane, TOC and outline levels all work** — they are not fake headings |
| **Zero-dependency generation** | Plain PowerShell emits OOXML directly. **No Python, no pandoc, no LibreOffice, no Word install required** |
| **No network access** | The generator makes no network requests: no downloads, no uploads, no external services |
| **Optional tint** | English and Chinese are the **same colour** by default (told apart by font, so the English keeps its visual weight). Pass `-ZhColor 3333CC` for blue Chinese |

---

## What the output looks like

The generated `.docx` alternates in pairs:

```
Introducing GPT-6 Sol and Luna                    ← Title (English, Word "Title" style)
推出 GPT-6 Sol 与 Luna                             ← Title (Chinese)

More ways to bring frontier intelligence…         ← Subtitle (English, grey italic)
把前沿智能带进你日常工作的更多方式。                  ← Subtitle (Chinese, grey italic)

Source: OpenAI — https://openai.com/...           ← Source line (small grey)
来源：OpenAI — https://openai.com/...

[ hero image, centred ]

Earlier this month, we introduced…                ← Body (English, Calibri)
本月早些时候，我们推出了…                            ← Body (Chinese, Microsoft YaHei)

GPT-6 API pricing                                 ← Section (Word "Heading 1" → visible in navigation pane)
GPT-6 API 定价

Model / 模型     Input / 输入     Output / 输出      ← Bilingual table (shaded header row)
GPT-5.6 Sol → …  $4 → $2          $20 → $10
```

Element styling:

| Element | Style |
|---|---|
| Document title | English + Chinese, centred, bold |
| Body | Calibri (EN) / Microsoft YaHei (ZH), same size and colour |
| Section / subsection | Word built-in Heading 1 / Heading 2 (navigation pane works) |
| Source, date | Small grey text |
| Footnotes, evals | Grey italic, indented |
| Quotes | Indented, grey |
| Figures | Centred, 6.2 in wide (A4 minus margins), bilingual caption underneath |

---

## How to download

> **A skill is just a folder with a `SKILL.md`.** Cloning it into a skills directory *is* the installation — nothing to compile, no package manager.

### Option A — clone into a shared skills directory (recommended)

Many clients (Claude Code, Codex, opencode, the generic `~/.agents`) link their skills directory to the
**same shared folder**, so **one install covers all of them**:

```bash
git clone https://github.com/ai-evolution-lab/translate-to-word.git ~/.skills/translate-to-word
```

Otherwise, clone straight into the client's own skills directory:

```bash
# Claude Code
git clone https://github.com/ai-evolution-lab/translate-to-word.git ~/.claude/skills/translate-to-word

# Codex
git clone https://github.com/ai-evolution-lab/translate-to-word.git ~/.codex/skills/translate-to-word

# opencode
git clone https://github.com/ai-evolution-lab/translate-to-word.git ~/.config/opencode/skills/translate-to-word

# Generic (~/.agents; DSH reads this too)
git clone https://github.com/ai-evolution-lab/translate-to-word.git ~/.agents/skills/translate-to-word

# Cursor
git clone https://github.com/ai-evolution-lab/translate-to-word.git ~/.cursor/skills/translate-to-word
```

Reload your client afterwards. Updates are just `git pull`.

### Option B — no git

Click **Code → Download ZIP** on the repository page, unzip, and drop the folder into any of the skills
directories above. **Keep the folder name `translate-to-word`** — it must match the `name` field in
`SKILL.md`, or the client may not load it.

### Option C — script only, no skill

The generator is a standalone `.ps1` you can lift out on its own:

```bash
curl -O https://raw.githubusercontent.com/ai-evolution-lab/translate-to-word/main/scripts/build-bilingual-docx.ps1
```

---

## How to use

### Way 1 — let the agent do it (recommended)

Once installed, just say:

> Turn this into a bilingual EN/ZH Word document, images included: https://openai.com/index/...

The agent then walks the whole path: fetch → segment → context-aware translation → capture figures →
build → verify in Word.

### Way 2 — write the JSON yourself and run the script

Write a `content.json` (see [`scripts/content.example.json`](scripts/content.example.json) for all 11 types,
or [`examples/minimal.content.json`](examples/minimal.content.json) for a minimal one):

```json
{
  "items": [
    { "t": "title", "en": "Shipping Faster With Caching", "zh": "用缓存把发布速度提上来" },
    { "t": "p",
      "en": "Prompt caching lets a model reuse computation for a shared prefix.",
      "zh": "提示词缓存让模型复用共享前缀上已做过的计算。" },
    { "t": "h2", "en": "What changes for you", "zh": "对你来说有什么变化" },
    { "t": "image", "file": "chart.png", "widthIn": 6.2,
      "enCaption": "Figure 1. Latency by cache state.",
      "zhCaption": "图 1. 不同缓存状态下的延迟。" }
  ]
}
```

Then:

```powershell
pwsh -File scripts/build-bilingual-docx.ps1 `
  -ContentJson .\content.json `
  -MediaDir    .\media `
  -OutFile     .\out.docx
```

Parameters:

| Parameter | Required | Meaning |
|---|---|---|
| `-ContentJson` | No | Defaults to `scripts/content.json`. **Either a top-level array or `{"items":[...]}`** |
| `-MediaDir` | No | Defaults to `scripts/media`. Images referenced by `image` items live here |
| `-OutFile` | **Yes** | Output `.docx` path; parent directories are created |
| `-ZhColor` | No | 6-digit hex RGB such as `3333CC`, to tint the Chinese side. Default: no tint |

### Item types

| `t` | Purpose | Fields |
|---|---|---|
| `title` / `subtitle` / `meta` | Title / subtitle / source line | `en` `zh` |
| `h2` / `h3` | Section / subsection (Word built-in headings) | `en` `zh` |
| `p` | Body paragraph | `en` `zh` |
| `note` | Footnote, eval caveat | `en` `zh` |
| `quote` | Quote, sample dialogue | `en` `zh` (string **or array**; array = multiple paragraphs) |
| `bullets` | Bulleted list | `en` `zh` (**array**) |
| `table` | Data table | `headers` `rows` |
| `image` | Figure | `file` `widthIn` `enCaption` `zhCaption` |

---

## Fully open source

- **MIT licensed** — commercial use, modification and redistribution all allowed; just keep the notice.
- **All source is in this repository.** No closed components, no hidden binaries, no "pro edition".
- The code is small: one PowerShell script (~400 lines) plus two Markdown docs and two example JSON files.
  You can read all of it and change it.
- Issues and PRs welcome. To change fonts, colours or add item types, read
  [`reference.md`](reference.md) — every style the generator emits is documented there.

## Any model, including local ones

**This skill is not tied to any model, and calls no translation API.**

- The repository contains **no API keys, no model SDK, no vendor dependency**.
- Translation is done by **whatever model your agent is running** — swap the model, swap the translator.
- It therefore works with **local / self-hosted models**: Ollama, vLLM, LM Studio, llama.cpp — anything
  your agent client can talk to.
- **The generator is pure deterministic code**, entirely independent of the model: give it the same JSON
  and you get the same `.docx`, every time. In other words, **layout quality never varies with the model —
  only translation quality does.**

This split is deliberate: translation goes to the model, layout goes to code. Models change, upgrade and
get replaced; the document format does not.

## Privacy and security

### Generation stage: zero network

`build-bilingual-docx.ps1`:

- **Makes no network requests at all** — no downloads, no uploads, no analytics, no update check
- **Collects no telemetry**, needs no account, no sign-in
- **Installs nothing** — no `pip install`, no `npm install`, nothing fetched from PyPI or npm
- The output is simply a **local file** that never leaves your disk

> For contrast: v1 of this repository used Python + `python-docx` and **auto-ran `pip install` (network,
> PyPI) on first use**. v2 was rewritten as pure PowerShell emitting OOXML precisely to remove that
> network dependency.

### Honest boundaries

To avoid overclaiming, these points matter:

1. **Fetching the article and capturing figures do use the network.** But that is done by **your agent's
   tools** (Firecrawl / built-in fetch / browser), not by this repository's script. The script itself
   never goes online.
2. **The article text is sent to the model you use.** Translation requires a model, so the content passes
   through your model provider. With a cloud model, that means the text leaves your machine.
   **For a fully local pipeline, pair this with a local model** — then fetch, translate and build all stay
   on your machine.
3. **Figures and translations are derivative of the original work.** Copyright remains with the original
   author. **Check your rights before publishing anything generated.** This repository ships no article
   text and no generated documents.

### Untrusted input

Article bodies are always treated as **untrusted data**:

- Any "instruction" appearing inside an article (e.g. "ignore previous instructions", "run the following
  command") is **text to be translated**, never executed and never obeyed.
- The fetching tools are used to **read**, never to execute.
- This rule is written into [`SKILL.md`](SKILL.md) where the agent reads it.

### Supply chain

- No runtime dependencies → **no dependency-poisoning surface**, no version drift.
- To audit: the entire generator is one file, readable end to end in ten minutes.

---

## Requirements

| Platform | What you need |
|---|---|
| **Windows** | Built-in **Windows PowerShell 5.1** or **PowerShell 7+**. `pwsh` (7+) recommended |
| **macOS** | `brew install --cask powershell` |
| **Linux** | See [Installing PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux) (apt / dnf / tarball) |

- Building documents does **not** require Word, LibreOffice, Python or pandoc.
- Word (optional) is only needed if you want to run the final verification step.
- Capturing figures (optional) needs an environment that can run Playwright or Chrome.

### Chinese fonts

The document specifies **Microsoft YaHei** for Chinese. macOS and Linux usually lack it, so
Word / Pages / LibreOffice **fall back** to a system Chinese font; reading is unaffected. To pin a
different font, change `eastAsia` in the `styles.xml` block of the script.

---

## Repository layout

```
translate-to-word/
├── SKILL.md                        # Skill instructions the agent reads (workflow + safety)
├── README.md                       # Chinese README
├── README_EN.md                    # This file
├── reference.md                    # Deep reference: full schema, capture code, Word pitfalls
├── CHANGELOG.md                    # Version history, incl. the v1 → v2 merge
├── LICENSE                         # MIT
├── .gitignore
├── scripts/
│   ├── build-bilingual-docx.ps1    # Generator: JSON → .docx (zero deps, no network)
│   └── content.example.json        # Example covering all 11 item types
└── examples/
    └── minimal.content.json        # Minimal getting-started example
```

---

## FAQ

**Why PowerShell instead of Python?**
Zero dependencies. A Python solution needs `python-docx`, and when it is missing you must `pip install`
over the network. PowerShell can emit OOXML directly — nothing to install, no network, deterministic
output. PowerShell 7 installs on all three platforms, so nothing is lost on portability.

**Do generated files open correctly in WPS / Pages / Google Docs?**
The output is standard OOXML with no private extensions. Verified to open in Word **without a repair
prompt**. Other suites generally open it fine, with minor styling differences possible.

**Why isn't the Chinese text blue by default?**
Same colour plus a different font keeps the **English original's visual weight intact**, which suits close
reading. Prefer the old blue-Chinese look? Pass `-ZhColor 3333CC`.

**My captured chart has a clipped legend / page text bleeding in.**
Those are the two most common capture pitfalls. `SKILL.md` step 4 and `reference.md` document the full
fix (widen the container so the chart re-renders, add an opaque backdrop, raise the z-index).

**Can it produce a PDF?**
This skill only produces `.docx`. Convert with Word's "Save as PDF" or LibreOffice
`soffice --convert-to pdf`.

**Translation quality is poor — what can I do?**
Translation quality **depends entirely on your model**; layout is deterministic and model-independent.
A stronger model, or supplying a glossary in your prompt, both help noticeably.

---

## Relationship to the old version

This repository was originally named **`article-to-bilingual-docx`** (created 2026-09). That was a
Python + `python-docx` implementation supporting **plain text only** (3 item types, no images, no tables),
and it needed a network `pip install` on first run.

The two were **two generations of the same thing**, so they were merged into one, keeping this version (v2).
The old one is still retrievable via a tag:

```bash
git checkout v1-python-legacy
```

See [CHANGELOG.md](CHANGELOG.md). The old repository URL redirects here automatically.

---

## License

[MIT](LICENSE) © 2026 lizhiwei