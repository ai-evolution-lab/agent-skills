# WPS COM 进阶参考

均基于 SKILL.md 的探测与坑点前提；对象模型与微软 Office VBA 基本一致。

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
 vals = $ws.Range($ws.Cells.Item(1,1), $ws.Cells.Item($r,$c)).Value2   # 二维数组
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

## 常见故障 → 处置

| 现象 | 处置 |
|---|---|
| `Presentations.Add()` 抛异常 | 确认 Visible=true；再试 `PowerPoint.Application` |
| 弹「是否保存」卡住 | 关闭时补 `Close(0)` / `Close($false)` |
| 找不到 Styles("标题 1") | 用常量索引 `-2 / -3 / -1` |
| Value2 单格取回不是数组 | 行列都只有 1 时按标量处理 |
| 中文乱码 | 脚本以 UTF-8 传给 pwsh；避免再经 cmd 中转 |
