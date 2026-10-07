# translate-to-word — reference

`SKILL.md` 是流程；本文件是可复用的细节、代码片段和完整 schema。

---

## 1. content.json 完整 schema

顶层可以是**数组**，也可以是 `{ "_comment": "...", "items": [ ... ] }`。顺序即文档顺序。

### 1.1 通用规则

- 除 `table` / `image` 外，每个条目的 `en` 与 `zh` 都必填，输出时**先英文后中文**。
- `en` / `zh` 通常为字符串；`quote` 和 `bullets` 允许**字符串数组**表示多段/多条。
- 未知的 `t` 会打 warning 并跳过，不会中断构建。

### 1.2 文本类条目

```jsonc
{ "t": "title",    "en": "Introducing GPT-6 Sol and Luna", "zh": "推出 GPT-6 Sol 与 Luna" }
{ "t": "subtitle", "en": "…", "zh": "…" }
{ "t": "meta",     "en": "Source: https://…", "zh": "来源：https://…" }
{ "t": "h2",       "en": "GPT-6 API pricing", "zh": "GPT-6 API 定价" }
{ "t": "h3",       "en": "Professional work", "zh": "专业工作" }
{ "t": "p",        "en": "…", "zh": "…" }
{ "t": "note",     "en": "…", "zh": "…" }
```

`h2` 映射到 Word 的 **Heading 1**，`h3` 映射到 **Heading 2**（文章标题是文档标题）。

### 1.3 多段引用

```jsonc
{ "t": "quote",
  "en": ["[Prompt] Website's looking clean! …", "Done — open the live site."],
  "zh": ["［提示词］网站看起来挺干净了……", "完成了——打开线上站点看看。"] }
```

### 1.4 列表

```jsonc
{ "t": "bullets",
  "en": ["Monitor and diagnose. …", "Adjust reasoning effort …", "Optimize which prefixes …"],
  "zh": ["监控与诊断。……", "在不破坏缓存的前提下调整推理强度……", "优化哪些前缀被缓存。……"] }
```

`en` 与 `zh` 数组长度不必相等，但成对列表应保持一致，方便对照阅读。

### 1.5 表格

表格做成**单张双语表**，不拆成中英两张——单元格多是数字和模型名，拆开反而更难对照。
表头写成 `EN / 中文` 形式。

```jsonc
{ "t": "table",
  "headers": ["Model / 模型", "Input / 输入", "Output / 输出", "Price reduction / 降价幅度"],
  "rows": [
    ["GPT-5.6 Sol → GPT-6 Sol",  "$4 → $2",    "$20 → $10",   "50% cheaper / 便宜 50%"],
    ["GPT-5.6 Luna → GPT-6 Luna","$0.20 → $0.10","$1.20 → $0.50","50% cheaper / 便宜 50%"]
  ] }
```

列宽由脚本自动分配（4 列等宽；3 列按 3249/1444/4333 twips）。表头行有浅蓝底纹并设为重复表头行。

### 1.6 图片

```jsonc
{ "t": "image",
  "file": "chart-0-automationbench.png",   // 相对 -MediaDir
  "widthIn": 6.2,                          // 成品宽度（英寸）；高按原图比例自动算
  "enCaption": "Figure 1. AutomationBench — score vs. cost per task.",
  "zhCaption": "图 1. AutomationBench——得分与每任务成本。" }
```

- `file` 支持 **PNG / JPEG**（脚本自己解析尺寸，无外部依赖）。
- `widthIn` 省略时默认 6.2 英寸（A4 减去左右各 1 英寸边距后的可用宽度）。
- 高度超过 8.4 英寸会自动按比例缩小，避免超出页面。
- `enCaption` / `zhCaption` 留空则**不输出**该题注（hero 装饰图就用空题注）。
- 同一个 `file` 重复引用只会嵌入一次。

---

## 2. 抓取文章图表

### 2.1 先枚举，判断哪些属于正文

```js
() => {
  const main = document.querySelector('main') || document.body;
  return {
    imgs: Array.from(main.querySelectorAll('img')).map((el, i) => ({
      i, alt: el.alt, src: el.src.slice(0, 120),
      natural: el.naturalWidth + 'x' + el.naturalHeight
    })),
    charts: main.querySelectorAll('.vega-embed, canvas, svg').length,
    // 很多站点用 vega-embed / chart.js / recharts 等容器类名
  };
}
```

正文 hero 图 + 正文图表要；"相关阅读"卡片缩略图、logo、图标不要。

### 2.2 图表是懒加载的，必须先滚完整页

```js
async () => {
  const H = document.body.scrollHeight;
  for (let y = 0; y <= H; y += 500) { window.scrollTo(0, y); await new Promise(r => setTimeout(r, 220)); }
  window.scrollTo(0, 0);
  await new Promise(r => setTimeout(r, 800));
  const charts = Array.from(document.querySelectorAll('.vega-embed'));
  charts.forEach((el, i) => el.setAttribute('data-xchart', String(i)));   // 打标记，方便选择器定位
  return charts.map((el, i) => ({
    i,
    box: Math.round(el.getBoundingClientRect().width) + 'x' + Math.round(el.getBoundingClientRect().height),
    text: (el.innerText || '').replace(/\s+/g, ' ').slice(0, 110)          // 用标题确认图表身份
  }));
}
```

### 2.3 找到图表的**外层容器**

图表标题和图例通常是 HTML，位于图表 SVG **外面**的容器里。只截 `.vega-embed` 会丢掉标题和图例。

OpenAI 类站点的容器类名是 `dotcom-chart-theme-scope`；其他站点按类名特征找（`chart`、`figure`、`graph`）。
从图表元素向上找到容器，并在祖先中找**最近的有背景色的元素**——那就是面板底色。

### 2.4 加宽 + 不透明底色 + 提升层级，然后截图

页面布局常把图表容器压窄（例如容器 447px 而图表本身 540px），导致**图例被裁掉**。
把容器加宽后图表会按新宽度**重新渲染**（Vega `fit-x` 会重排，不是简单拉伸），图例就有位置了。

容器/SVG 背景常是透明的，直接截图会混入页面其他内容，所以还要给容器加底色并提升层级。

```js
async (page) => {
  const W = 640;                                  // 加宽后的容器宽度
  const results = [];
  const count = await page.locator('.vega-embed').count();

  for (let i = 0; i < count; i++) {
    const loc = page.locator('[data-xchart="' + i + '"]');

    const prep = await loc.evaluate((node, arg) => {
      const { idx, w } = arg;
      // 1) 向上找到图表外层容器
      let scope = node;
      while (scope && !(scope.className || '').toString().includes('dotcom-chart-theme-scope'))
        scope = scope.parentElement;
      if (!scope) return { err: 'no scope' };

      // 2) 找最近的有背景色的祖先 —— 面板底色
      let bg = '', p = scope;
      while (p && !bg) {
        const c = getComputedStyle(p).backgroundColor;
        if (c && c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent') bg = c;
        p = p.parentElement;
      }

      // 3) 保存原样式，加宽容器 + 不透明底色 + 提升层级，祖先解除裁剪
      const saved = [];
      let q = scope, n = 0;
      while (q && n < 8) {
        saved.push([q, q.style.width, q.style.maxWidth, q.style.overflow, q.style.position, q.style.zIndex, q.style.background]);
        q.style.overflow = 'visible';
        if (n === 0) {
          q.style.width = w + 'px'; q.style.maxWidth = 'none';
          q.style.position = 'relative'; q.style.zIndex = '2147483000';
          q.style.background = bg || '#000';
        }
        q = q.parentElement; n++;
      }
      window.__sc = window.__sc || {};
      window.__sc[idx] = saved;
      scope.setAttribute('data-xscope', '1');
      // 容器第一行文本就是图表标题，用它命名文件
      const lines = (scope.innerText || '').trim().split('\n').filter(s => s.trim());
      return { title: lines[0] || '', bg };
    }, { idx: i, w: W });

    if (prep && prep.err) { results.push({ i, err: prep.err }); continue; }

    await page.waitForTimeout(600);               // 等图表按新宽度重排
    const scopeLoc = page.locator('[data-xscope="1"]');
    await scopeLoc.scrollIntoViewIfNeeded();
    await page.waitForTimeout(350);

    const box = await scopeLoc.evaluate(n => {
      const r = n.getBoundingClientRect();
      return Math.round(r.width) + 'x' + Math.round(r.height);
    });
    await scopeLoc.screenshot({ path: '<落盘目录>/chart-' + i + '.png', scale: 'device', type: 'png' });

    // 4) 还原
    await page.evaluate((idx) => {
      ((window.__sc || {})[idx] || []).forEach(([el, w, mw, ov, pos, z, bg]) => {
        el.style.width = w; el.style.maxWidth = mw; el.style.overflow = ov;
        el.style.position = pos; el.style.zIndex = z; el.style.background = bg;
      });
      const s = document.querySelector('[data-xscope="1"]');
      if (s) s.removeAttribute('data-xscope');
    }, i);

    await page.waitForTimeout(250);
    results.push({ i, title: prep.title, box });
  }
  return results;                                 // 用 title 核对每张图的身份
}
```

要点：

- `scale: 'device'` 会乘以 devicePixelRatio（本机 1.75）。容器宽 640px → 实测约 **1122px** 宽，
  放进 Word 约 **178 DPI**，足够清晰。
- 每张图抓完**立刻还原**样式，否则会影响下一张的布局。
- **必须肉眼确认**每张图：图例是否完整、有没有混入页面其他文字、坐标轴刻度是否被裁。
  这一步不能靠尺寸或数量代替。

### 2.5 Playwright 的落盘位置

Playwright MCP 的 `filename` / `path` 相对的是 **MCP server 进程的工作目录**，不是当前项目目录，
也不是 `.playwright-mcp/`。截图后如果找不到文件，就在磁盘上搜文件名定位真实目录。

`browser_run_code_unsafe` 运行在受限 VM 里：**没有** `process`、也没有 `require('fs')`，
动态 `import()` 也会失败。所以**不能用 fs 写文件**，只能靠 Playwright 自己的 `screenshot({ path })` 落盘。

### 2.6 普通栅格图（hero 等）

`naturalWidth` 就是图片的真实像素上限。用 `scale: 'device'` 截 `<img>` 元素即可；
如果结果显示尺寸远大于 `naturalWidth`，那部分是插值出来的，可接受但不增加真实细节。

---

## 3. 生成器做什么

`scripts/build-bilingual-docx.ps1` 直接产出 OOXML（zip + XML），**不调用 Word / pandoc / python**。

| 步骤 | 说明 |
|---|---|
| XML 校验 | 每个 part 先 `[xml]` 解析，格式不对就报错退出 |
| 结构 | `[Content_Types].xml`、`_rels/.rels`、`word/document.xml`、`word/styles.xml`、`word/_rels/document.xml.rels`、`docProps/core.xml` |
| 图片 | 放进 `word/media/`，在 `document.xml.rels` 里加 image 关系，在 `[Content_Types].xml` 里按实际用到的扩展名加 `Default` |
| 字体 | 拉丁 Calibri、中日韩 Microsoft YaHei，设在 `docDefaults` 里，所有 run 继承 |
| 标题 | 样式名用 `heading 1` / `heading 2`，Word 会识别为内置标题 → 导航窗格与目录可用 |
| 页边距 | A4（11906×16838 twips），四边 1440 twips |

图片尺寸换算：**1 英寸 = 914400 EMU**；`cx = widthIn × 914400`，`cy` 按原图宽高比推算，超过 8.4 英寸则等比缩小。

### 3.1 中文染色（`-ZhColor`）

默认**不染色**：中英同字号同色，靠字体（Calibri / Microsoft YaHei）区分，
英文原文的视觉权重不被削弱。

传 `-ZhColor 3333CC` 时，脚本给每个**中文侧**的 run 加
`<w:rPr><w:color w:val="…"/></w:rPr>`，**覆盖样式自带的颜色**。覆盖范围：
`title` / `subtitle` / `meta` / `h2` / `h3` / `p` / `note` / `quote` / `bullets` 的中文段，
以及 `image` 的中文题注。**英文侧、表格、空行不受影响。**

值必须是 6 位十六进制（允许带 `#`），否则脚本直接报错退出，不会产出半成品。

> 注意：Word COM 读回的 `Font.Color` 是 **BGR** 排列的长整数。
> 传入 `#3333CC` 会读成 `0xCC3333`（= 13382451），**这是正常的**，不是颜色错了。

---

## 4. 校验产物

```powershell
$out = "$([Environment]::GetFolderPath('Desktop'))\文章标题 中英对照.docx"
$word = New-Object -ComObject Word.Application
$word.Visible = $false; $word.DisplayAlerts = 0
$doc = $null
try {
  $doc = $word.Documents.Open($out, $false, $true)      # ConfirmConversions=false, ReadOnly=true
  "Opened OK (no repair)"
  "Paragraphs  : $($doc.Paragraphs.Count)"
  "Tables      : $($doc.Tables.Count)"
  "InlineShapes: $($doc.InlineShapes.Count)"            # 应等于图片数
  "Pages       : $($doc.ComputeStatistics(2))"          # wdStatisticPages
  for ($i = 1; $i -le $doc.InlineShapes.Count; $i++) {
    $sh = $doc.InlineShapes.Item($i)
    "{0}. {1:N0} x {2:N0} pt" -f $i, $sh.Width, $sh.Height
  }
  $all = $doc.Content.Text
  foreach ($k in @('英文标题','中文标题','Figure 1','图 1')) { "{0} : {1}" -f $k, $all.Contains($k) }
} finally {
  if ($doc) { try { $doc.Close(0) } catch {} }
  try { $word.Quit() } catch {}
  Start-Sleep -Milliseconds 600
  Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
```

**"Opened OK (no repair)" 是最关键的信号**——说明生成的 OOXML 结构合法。

### 大纲层级抽查

```powershell
for ($i = 1; $i -le $doc.Paragraphs.Count; $i++) {
  $p = $doc.Paragraphs.Item($i)
  if ($p.OutlineLevel -lt 10) { "outlineLevel=$($p.OutlineLevel)  $($p.Style.NameLocal)" }
}
```

英文标题应为 1 级、英文小节为 2 级（中文标题同样成对出现）。

---

## 5. Word COM 的坑（本机 Word 12.0 / 2007）

| 坑 | 现象 | 处理 |
|---|---|---|
| `SaveAs([ref]$path, [ref]12)` | `Value does not fall within the expected range` / `RPC 服务器不可用 (0x800706BA)`，COM 实例直接崩 | 用**普通参数** `$doc.SaveAs($path, 12)`。本 skill 生成端不走 Word，只在校验时用 COM 读 |
| 内置样式名 | 中文版 Word 是"正文""标题 1""列表项目符号"，按英文名取会失败 | 按 `WdBuiltinStyle` **数值**取：Normal=-1、Heading1=-2、Heading2=-3、Heading3=-4、Title=-63、Subtitle=-75、ListBullet=-49 |
| `$word.Quit()` | 关闭后偶发 `RPC 服务器不可用` | 无害；之后确认并清理残留 `WINWORD` 进程 |
| 文件被占用写不进去 | 产物正被别的程序打开（编辑器 / 预览面板 / 同步盘） | 检测独占打开失败后**换文件名**输出，或提示用户关闭预览 |

检测文件是否被占用：

```powershell
try { $fs = [IO.File]::Open($path, 'Open', 'ReadWrite', 'None'); $fs.Close(); '可写' }
catch { '被占用' }
```

---

## 6. 参考环境（排查时先看这里）

本 skill 是在下面这套环境里开发并验证的。你的环境可能不同，但这些"坑"的成因是通用的：

- 无 `pandoc`、无 `libreoffice`/`soffice`。
- `python` 指向 `WindowsApps\python.exe`（Microsoft Store 空壳，`-c` 无任何输出）；
  无 `python-docx`、无 `lxml`。**这正是 v2 放弃 Python 方案的原因。**
- Word 版本 **12.0**（Office 2007），`Word.Application` COM 可用。
- `pwsh` 为 **PowerShell 7.6.5**。
- 桌面路径**可能被 OneDrive 重定向**：用 `[Environment]::GetFolderPath('Desktop')` 取真实路径，
  不要硬编码 `$HOME\Desktop`。
- 显示器缩放 175% → Playwright `scale:'device'` 实际放大 1.75 倍。

> 因此本 skill 的生成端**刻意不依赖任何外部工具**，只用 PowerShell 直接拼 OOXML。