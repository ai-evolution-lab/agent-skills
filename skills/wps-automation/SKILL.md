---
name: wps-automation
description: 跨平台办公文档自动化。Windows：PowerShell COM 驱动本机 WPS Office（KWPP 演示 / KWPS 文字 / KET 表格）新建、编辑、另存 pptx/docx/xlsx 并导出 PDF，支持批量转换。macOS / Linux / 无 WPS 的机器：OOXML 直造路线（python-docx / python-pptx / openpyxl，或 zip+XML 零依赖手写）完成同样的文档生成、修改与内容读取。当用户要求做 PPT、写或改 Word、处理 Excel、生成办公文档、批量转 PDF、格式转换，或提到 WPS、pptx、docx、xlsx 的本地文件操作时使用。
platforms: [windows, macos, linux]
does:
  - Windows：驱动本机 WPS 新建/编辑 PPT、Word、Excel，另存 pptx/docx/xlsx、批量导出 PDF
  - macOS / Linux：纯代码生成/修改/读取 pptx、docx、xlsx（OOXML 直造，零 GUI）
  - 跨平台：既有文档内容审阅、摘要、批量文本替换
boundary: COM 渲染级能力（套模板效果验证、图表渲染成图、重排检查）仅 Windows；Mac 的 PDF 导出依赖 LibreOffice（soffice），未装则只能交付 Office 格式；不能操作 WPS 云文档与登录态
---

# 办公文档自动化（Win: WPS COM ｜ Mac·Linux: OOXML 直造）

## 第 0 步 · 平台与能力探测（先跑再动手）

```powershell
# Windows（pwsh）：COM 是否注册
Test-Path "Registry::HKEY_CLASSES_ROOT\KWPP.Application"   # True → A 路线
```

```bash
# macOS / Linux：
python3 --version 2>/dev/null || echo "无 python3"   # 有 → B 路线用 python 库
which soffice 2>/dev/null || echo "无 LibreOffice"   # 有 → 才能转 PDF
```

- **A 路线（Windows + WPS COM）**：能力最全——真实渲染、套模板、公式、PDF/图片导出、格式级编辑。
- **B 路线（macOS / Linux / 无 WPS 的 Windows）**：能新建、改文本、读内容、批量替换；做不了渲染相关的事。
- **Mac 的 WPS 没有 COM / AppleScript 自动化接口，不要尝试在 Mac 驱动 WPS**——直接走 B 路线。
- A 路线若 KW* ProgID 报错，可降级用兼容 ProgID：`PowerPoint.Application` / `Word.Application` / `Excel.Application`（WPS 注册了同一套兼容层）。

## 能力对照（选路线用）

| 操作 | A: Win COM | B: OOXML 直造 |
|---|---|---|
| 新建 pptx/docx/xlsx | ✅ | ✅ |
| 改文本 / 批量替换（保留其余格式） | ✅ | ✅ |
| 读取内容 / 摘要 | ✅ | ✅ |
| 导出 PDF | ✅ 内置 | ⚠️ 需 LibreOffice（`soffice`） |
| 套 WPS/Office 模板并验证渲染效果 | ✅ | ❌ |
| 图表渲染成图片 | ✅ | ❌ |
| 公式 / 数据透视 | ✅ | 部分（openpyxl 可写公式） |

---

## A 路线 · Windows WPS COM（实测）

在 WPS Office 12.x 上验证。所有操作用 `pwsh -Command` 一段跑完，不必建中间脚本文件。

### 速查表

| 组件 | ProgID | 另存格式码 |
|---|---|---|
| 演示 (PPT) | `KWPP.Application` | `SaveAs(path, 24)` = pptx；`32` = PDF |
| 文字 (Word) | `KWPS.Application` | `SaveAs2(path, 12)` = docx；`17` = PDF |
| 表格 (Excel) | `KET.Application` | `SaveAs(path, 51)` = xlsx；PDF 用 `ExportAsFixedFormat(0, path)` |

演示版式常量 `Slides.Add(序号, 版式)`：`1`=标题页、`2`=标题+文本页、`12`=空白页。

### 新建 PPT（实测模板）

```powershell
$ErrorActionPreference = 'Stop'
$app  = New-Object -ComObject KWPP.Application
try { $app.Visible = $true } catch {}      # 演示组件拒绝隐藏运行，必须 true
$pres = $app.Presentations.Add()
$s1 = $pres.Slides.Add(1, 1)               # 标题页
$s1.Shapes.Item(1).TextFrame.TextRange.Text = "主标题"
$s1.Shapes.Item(2).TextFrame.TextRange.Text = "副标题 · $(Get-Date -Format 'yyyy-MM-dd')"
$s2 = $pres.Slides.Add(2, 2)               # 文本页
$s2.Shapes.Item(1).TextFrame.TextRange.Text = "第二页标题"
$s2.Shapes.Item(2).TextFrame.TextRange.Text = "正文行1`n正文行2"
$pres.SaveAs("D:\out\demo.pptx", 24)
$pres.Close(); $app.Quit()
```

### 新建 Word（实测模板）

```powershell
$w   = New-Object -ComObject KWPS.Application
$doc = $w.Documents.Add()
$sel = $w.Selection
$sel.TypeText("正文内容")
$sel.TypeParagraph()
$doc.SaveAs2("D:\out\demo.docx", 12)
$doc.Close(0)          # 0 = 不再保存，避免退出弹保存框
$w.Quit()
```

### 新建 Excel（模板）

```powershell
$x  = New-Object -ComObject KET.Application
$wb = $x.Workbooks.Add()
$ws = $wb.Worksheets.Item(1)
$ws.Cells.Item(1, 1) = "姓名"; $ws.Cells.Item(1, 2) = "得分"
$ws.Range("A2:B4").Value2 = @(
  @("甲", 90), @("乙", 85), @("丙", 78)
)
$wb.SaveAs("D:\out\demo.xlsx", 51)
$wb.Close($false); $x.Quit()
```

### 批量转 PDF（Word 目录 → PDF）

```powershell
$w = New-Object -ComObject KWPS.Application
$w.Visible = $false                       # 文字/表格组件可以隐藏运行
foreach ($f in Get-ChildItem "D:\docs" -Filter *.docx) {
  $doc = $w.Documents.Open($f.FullName)
  $doc.ExportAsFixedFormat((Join-Path "D:\pdf" ($f.BaseName + ".pdf")), 17)
  $doc.Close(0)
}
$w.Quit()
```

PPT 批量同理：`$pres.SaveAs($pdf, 32)`；表格用 `$ws.ExportAsFixedFormat(0, $pdf)`。

### A 路线的坑（都踩过）

1. `SaveAs` 一律传**绝对路径**。
2. **KWPP 必须 `Visible = $true`**，KWPS / KET 可隐藏。
3. 关闭用 `$doc.Close(0)` / `$wb.Close($false)` / `$pres.Close()`，否则可能卡保存对话框。
4. 用户正开着 WPS 时，`New-Object` 会附加到已有实例，`Quit()` 会把用户的窗口一起关掉。动手前先探测 `Get-Process wps,et,wpp -ErrorAction SilentlyContinue`；已在运行就只关闭自己新建的文档、不要 `Quit()`，并提醒用户。
5. 脚本中途报错会残留 WPS 进程；确认用户没有未保存文档后才可 `Get-Process wps* | Stop-Process` 清理。
6. `SaveAs(path, 码)` 抛异常时去掉格式码重试一次，或换兼容 ProgID。
7. 生成后必须验证：文件存在且 Length > 0，再向用户交付。
8. 用户明确要求用 WPS 打开看效果时，保存后 `Start-Process $path` 即可，勿再开 COM 编辑。

---

## B 路线 · OOXML 直造（macOS / Linux / 无 WPS 的 Windows）

依赖二选一：优先 `pip3 install python-pptx python-docx openpyxl`（Mac 自带 python3，缺 pip 先装）；完全无 python 时用 reference.md 的 zip+XML 手写法。

### 新建 PPT

```python
from pptx import Presentation
prs = Presentation()
s = prs.slides.add_slide(prs.slide_layouts[0])   # 0=标题页
s.shapes.title.text = "主标题"
s.placeholders[1].text = "副标题"
s2 = prs.slides.add_slide(prs.slide_layouts[1])  # 1=标题+内容页
s2.shapes.title.text = "第二页标题"
s2.placeholders[1].text = "正文行1\n正文行2"
prs.save("/path/out.pptx")
```

### 新建 Word

```python
from docx import Document
doc = Document()
doc.add_heading("文档标题", level=1)
doc.add_paragraph("正文内容")
doc.save("/path/out.docx")
```

### 新建 Excel

```python
from openpyxl import Workbook
wb = Workbook(); ws = wb.active
ws.append(["姓名", "得分"]); ws.append(["甲", 90]); ws.append(["乙", 85])
wb.save("/path/out.xlsx")
```

### 批量转 PDF（装了 LibreOffice 才可用；`brew install --cask libreoffice`）

```bash
soffice --headless --convert-to pdf --outdir ./pdf ./docs/*.docx ./docs/*.pptx
```

### B 路线的坑

1. python-pptx 的 `slide_layouts` 索引随模板变化，默认模板 0=标题、1=标题+内容。
2. python-docx 设中文字体要同时设 `run.font.name` 和 `rPr.rFonts` 的 eastAsia 属性，否则中文回退宋体。
3. openpyxl 不支持读老格式 `.xls`，先转 `.xlsx` 再处理。
4. 生成后同样验证文件存在且非 0 字节，再交付。

## 进阶操作

A 路线高级操作（既有文档编辑、插图、表格、样式、查找替换）与 B 路线进阶（保留格式的批量替换、zip+XML 手写法）见 [reference.md](reference.md)。
