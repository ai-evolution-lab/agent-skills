---
name: wps-automation
description: 在 Windows 上用 PowerShell COM 驱动本机 WPS Office（KWPP 演示 / KWPS 文字 / KET 表格）新建、编辑、另存 pptx/docx/xlsx 并导出 PDF，支持批量转换。当用户要求做 PPT、写或改 Word、处理 Excel、生成办公文档、批量转 PDF、格式转换，或提到 WPS、pptx、docx、xlsx 的本地文件操作时使用。本机 WPS COM 不可用时降级为不启动 WPS 直接读写 OOXML 文件。
platforms: [windows]
does:
  - 驱动本机 WPS 新建/编辑 PPT、Word、Excel 文档
  - 另存 pptx/docx/xlsx 与批量导出 PDF
  - 读取既有文档做内容审阅/摘要
boundary: 仅 Windows + WPS 12.x COM；不能操作 WPS 云文档与登录态；用户开着 WPS 时避免 Quit
---

# WPS 文档自动化（本机 COM）

在 WPS Office 12.x + Windows 上实测验证。所有操作用 `pwsh -Command` 一段跑完，不必建中间脚本文件。

## 第 0 步 · 探测

```powershell
Test-Path "Registry::HKEY_CLASSES_ROOT\KWPP.Application"   # True → COM 可用
```

False（非 Windows / 未装 WPS）→ 跳到文末「OOXML 兜底」。
若 KW* 报错，可降级用兼容 ProgID：`PowerPoint.Application` / `Word.Application` / `Excel.Application`（WPS 注册了同一套兼容层）。

## 速查表

| 组件 | ProgID | 另存格式码 |
|---|---|---|
| 演示 (PPT) | `KWPP.Application` | `SaveAs(path, 24)` = pptx；`32` = PDF |
| 文字 (Word) | `KWPS.Application` | `SaveAs2(path, 12)` = docx；`17` = PDF |
| 表格 (Excel) | `KET.Application` | `SaveAs(path, 51)` = xlsx；PDF 用 `ExportAsFixedFormat(0, path)` |

演示版式常量 `Slides.Add(序号, 版式)`：`1`=标题页、`2`=标题+文本页、`12`=空白页。

## 新建 PPT（实测模板）

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

## 新建 Word（实测模板）

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

## 新建 Excel（模板）

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

## 批量转 PDF（Word 目录 → PDF）

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

## 坑（都踩过）

1. `SaveAs` 一律传**绝对路径**。
2. **KWPP 必须 `Visible = $true`**，KWPS / KET 可隐藏。
3. 关闭用 `$doc.Close(0)` / `$wb.Close($false)` / `$pres.Close()`，否则可能卡保存对话框。
4. 用户正开着 WPS 时，`New-Object` 会附加到已有实例，`Quit()` 会把用户的窗口一起关掉。动手前先探测 `Get-Process wps,et,wpp -ErrorAction SilentlyContinue`；已在运行就只关闭自己新建的文档、不要 `Quit()`，并提醒用户。
5. 脚本中途报错会残留 WPS 进程；确认用户没有未保存文档后才可 `Get-Process wps* | Stop-Process` 清理。
6. `SaveAs(path, 码)` 抛异常时去掉格式码重试一次，或换兼容 ProgID。
7. 生成后必须验证：`Get-Item $path` 存在且 Length > 0，再向用户交付。
8. 用户明确要求用 WPS 打开看效果时，保存后 `Start-Process $path` 即可，勿再开 COM 编辑。

## 进阶操作

打开既有文档并修改、插图、表格、标题样式、查找替换等见 [reference.md](reference.md)。

## OOXML 兜底（无 WPS 时）

`.docx/.pptx/.xlsx` 本体是 zip+XML。非 Windows 或无 WPS 时直接读写文件生成（Python 用 python-docx / python-pptx；无依赖时解压改 XML 再打包）。适合纯内容生成与读取；渲染检查、套模板效果、导出 PDF 仍需本机 WPS COM。
