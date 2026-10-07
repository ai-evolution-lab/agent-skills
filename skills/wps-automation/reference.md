# wps-automation 进阶参考

A 路线 = Windows WPS COM；B 路线 = OOXML 直造（macOS / Linux / 无 WPS）。
均基于 SKILL.md 第 0 步的探测与坑点前提。

---

# A 路线 · WPS COM 进阶（Windows）

对象模型与微软 Office VBA 基本一致。

## 打开并修改既有文档

```powershell
$w   = New-Object -ComObject KWPS.Application
$doc = $w.Documents.Open("D:\docs\报告.docx")
# 全文查找替换
$w.Selection.Find.ClearAll()
$w.Selection.Find.Execute("旧词", $false, $false, $false, $false, $false, $true, 1, $false, "新词", 2)  # 2 = wdReplaceAll
# 文末追加
$w.Selection.EndKey(6) | Out-Null    # 6 = wdStory
$w.Selection.TypeParagraph(); $w.Selection.TypeText("追加内容")
$doc.Save()
$doc.Close(0); $w.Quit()
```

## Word：标题样式与加粗

样式用常量索引，避免中文版样式名不匹配：

```powershell
$sel = $w.Selection
$sel.Style = $doc.Styles.Item(-2)    # -2=标题1, -3=标题2, -1=正文
$sel.TypeText("第一章 概述")
$sel.Font.Bold = $true
$sel.Paragraphs.Item(1).Format.LineSpacingRule = 5   # 1.5 倍行距（5=wdLineSpace1pt5）
```

## PPT：插入图片 / 表格 / 文本框

```powershell
$app  = New-Object -ComObject KWPP.Application
$app.Visible = $true
$pres = $app.Presentations.Open("D:\out\demo.pptx")     # 打开既有
$slide = $pres.Slides.Add(3, 12)                        # 空白页
$slide.Shapes.AddPicture("D:\img\chart.png", $false, $true, 60, 50, 520, 300)  # 左/上/宽/高
$tbl = $slide.Shapes.AddTable(4, 3, 80, 80, 500, 240).Table
$tbl.Cell(1,1).Shape.TextFrame.TextRange.Text = "表头"
$tb = $slide.Shapes.AddTextbox(1, 60, 400, 520, 60)     # 1 = msoTextOrientationHorizontal
$tb.TextFrame.TextRange.Text = "备注文字"
$pres.SaveAs("D:\out\demo_v2.pptx", 24)
$pres.Close(); $app.Quit()
```

## PPT：读取内容（审阅 / 摘要）

```powershell
foreach ($s in $pres.Slides) {
  "第 $($s.SlideIndex) 页："
  foreach ($sh in $s.Shapes) { if ($sh.HasTextFrame) { $sh.TextFrame.TextRange.Text } }
}
```

## Excel：读取 / 汇总 / 图表截图

```powershell
$x  = New-Object -ComObject KET.Application
$wb = $x.Workbooks.Open("D:\data\成绩.xlsx")
$ws = $wb.Worksheets.Item("Sheet1")
$used = $ws.UsedRange
$r = $used.Rows.Count; $c = $used.Columns.Count
$vals = $ws.Range($ws.Cells.Item(1,1), $ws.Cells.Item($r,$c)).Value2   # 二维数组
$ws.Range("D2").Formula = "=SUM(B2:B$($r))"
$wb.SaveAs("D:\data\成绩_汇总.xlsx", 51)
$wb.Close($false); $x.Quit()
```

整表导出为图片：`$ws.Range(...).CopyPicture()` + 粘贴到图表对象再 `Chart.Export("png")`；不熟时改用 PDF 中转。

## 退出与残留清理

```powershell
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) | Out-Null
[GC]::Collect(); [GC]::WaitForPendingFinalizers()
# 仍残留且确认无用户未保存文档时：
Get-Process wps,et,wpp -ErrorAction SilentlyContinue | Stop-Process
```

## A 路线常见故障 → 处置

| 现象 | 处置 |
|---|---|
| `Presentations.Add()` 抛异常 | 确认 Visible=true；再试 `PowerPoint.Application` |
| 弹「是否保存」卡住 | 关闭时补 `Close(0)` / `Close($false)` |
| 找不到 Styles("标题 1") | 用常量索引 `-2 / -3 / -1` |
| Value2 单格取回不是数组 | 行列都只有 1 时按标量处理 |
| 中文乱码 | 脚本以 UTF-8 传给 pwsh；避免再经 cmd 中转 |

---

# B 路线 · OOXML 直造进阶（macOS / Linux / 无 WPS）

## 保留格式的批量替换（python-docx）

`document.paragraphs` 逐 run 替换，不破坏字体/样式：

```python
from docx import Document
doc = Document("报告.docx")
for p in doc.paragraphs:
    for run in p.runs:
        if "旧词" in run.text:
            run.text = run.text.replace("旧词", "新词")
doc.save("报告_改.docx")
```

表格里的文本在 `doc.tables → row.cells → paragraphs`，同样逐 run 处理。

## 读取 pptx / xlsx 内容（审阅、摘要）

```python
from pptx import Presentation
prs = Presentation("demo.pptx")
for i, slide in enumerate(prs.slides, 1):
    print(f"第 {i} 页：")
    for shape in slide.shapes:
        if shape.has_text_frame:
            print(shape.text_frame.text)
```

```python
from openpyxl import load_workbook
wb = load_workbook("成绩.xlsx")          # data_only=True 可取公式计算值
ws = wb.active
for row in ws.iter_rows(values_only=True):
    print(row)
```

## 零依赖手写 OOXML（无 python 时，Mac 自带 zip/unzip）

`.docx/.pptx/.xlsx` 本体是 zip+XML。最小改文本流程：

```bash
mkdir /tmp/docxwork && cd /tmp/docxwork
unzip -o /path/报告.docx -d pkg
# 正文在 pkg/word/document.xml（pptx 是 ppt/slides/slideN.xml，xlsx 是 xl/sharedStrings.xml + xl/worksheets/sheetN.xml）
sed -i '' 's/旧词/新词/g' pkg/word/document.xml     # macOS sed 要 -i ''
cd pkg && zip -r -X ../报告_改.docx '[Content_Types].xml' _rels docProps word  # [Content_Types].xml 必须在包里
```

注意：
- 重打包必须包含 `[Content_Types].xml` 与 `_rels/`，顺序无所谓但**不能漏**。
- 只改文本走 sed 是安全的；改结构（加段落/页）请老实装 python。
- 中文字符在 XML 里通常直接 UTF-8 存储，grep/sed 前先 `grep -c '旧词'` 确认能匹配到。

## LibreOffice 批量转 PDF

```bash
# 安装：brew install --cask libreoffice
soffice --headless --convert-to pdf --outdir ./pdf 文件1.docx 文件2.pptx
soffice --headless --convert-to pdf --outdir ./pdf ./docs/*.xlsx
```

| 现象 | 处置 |
|---|---|
| `pip3 install` 报 externally-managed | 用 `pip3 install --user` 或 `python3 -m venv` |
| soffice 报已在运行 | 加 `-env:UserInstallation=file:///tmp/lo_profile` 用独立配置目录 |
| python-pptx 打开加密文件报错 | OOXML 直造不支持加密文档，回 A 路线（Windows）或让用户解密 |
| 生成的 docx 中文变宋体 | 见 SKILL.md B 路线坑 2（eastAsia 字体设置） |
