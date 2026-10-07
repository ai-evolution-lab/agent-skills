# build-bilingual-docx.ps1
# Builds a bilingual (EN/ZH) Word document from content.json, optionally embedding images.
# Content is paragraph-aligned: one English block followed by its Chinese counterpart.
# Requires: PowerShell 7+. No Word / pandoc / python dependency.
#
# Usage:
#   pwsh -File build-bilingual-docx.ps1 -ContentJson .\content.json -MediaDir .\media -OutFile "$HOME\Desktop\out.docx"
#
# Optional:
#   -ZhColor 3333CC     tint Chinese runs (default: same colour as English)
#
# Content JSON is either a top-level array of items, or { "items": [ ... ] }.
# Item types: title | subtitle | meta | h2 | h3 | p | note | quote | bullets | table | image

param(
  [string]$ContentJson = (Join-Path $PSScriptRoot 'content.json'),
  [string]$MediaDir    = (Join-Path $PSScriptRoot 'media'),
  [Parameter(Mandatory = $true)][string]$OutFile,
  [string]$ZhColor     = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

# Optional: tint the Chinese side. Empty (default) = same colour as English, so the two
# languages are told apart by font alone. Pass e.g. -ZhColor 3333CC for blue Chinese.
if ($ZhColor) {
  if ($ZhColor -notmatch '^#?[0-9A-Fa-f]{6}$') {
    throw "-ZhColor must be a 6-digit hex RGB value, e.g. 3333CC (got '$ZhColor')"
  }
  $ZhColor = $ZhColor.TrimStart('#').ToUpperInvariant()
}
$script:ZhColor = $ZhColor

# ---------------------------------------------------------------- helpers ----
function Esc([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}
function AsArray($v) {
  if ($null -eq $v) { return @() }
  if ($v -is [System.Array]) { return $v }
  return @($v)
}
function Para([string]$style, [string]$text, [string]$color = '') {
  $rPr = if ($color) { '<w:rPr><w:color w:val="' + $color + '"/></w:rPr>' } else { '' }
  '<w:p><w:pPr><w:pStyle w:val="' + $style + '"/></w:pPr><w:r>' + $rPr +
    '<w:t xml:space="preserve">' + (Esc $text) + '</w:t></w:r></w:p>'
}
function SpacerPara() { Para 'Spacer' '' }

# Reads PNG or JPEG dimensions without any external library.
function Get-ImageInfo([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "image not found: $Path" }
  $fs = [System.IO.File]::OpenRead($Path)
  try {
    $br  = [System.IO.BinaryReader]::new($fs)
    $sig = $br.ReadBytes(8)

    if ($sig.Length -ge 8 -and $sig[0] -eq 0x89 -and $sig[1] -eq 0x50) {   # PNG
      $fs.Position = 16
      $wb = $br.ReadBytes(4); $hb = $br.ReadBytes(4)
      $w = ([int]$wb[0]) * 16777216 + ([int]$wb[1]) * 65536 + ([int]$wb[2]) * 256 + [int]$wb[3]
      $h = ([int]$hb[0]) * 16777216 + ([int]$hb[1]) * 65536 + ([int]$hb[2]) * 256 + [int]$hb[3]
      return [pscustomobject]@{ W = $w; H = $h; Ext = 'png'; Mime = 'image/png' }
    }

    if ($sig.Length -ge 2 -and $sig[0] -eq 0xFF -and $sig[1] -eq 0xD8) {   # JPEG
      $fs.Position = 2
      while ($fs.Position -lt $fs.Length - 1) {
        if ($br.ReadByte() -ne 0xFF) { continue }
        $marker = $br.ReadByte()
        while ($marker -eq 0xFF) { $marker = $br.ReadByte() }
        if ($marker -ge 0xC0 -and $marker -le 0xCF -and $marker -ne 0xC4 -and $marker -ne 0xC8 -and $marker -ne 0xCC) {
          $null = ([int]$br.ReadByte()) * 256 + [int]$br.ReadByte() # frame header length
          $null = $br.ReadByte()                                  # precision
          $h = ([int]$br.ReadByte()) * 256 + [int]$br.ReadByte()
          $w = ([int]$br.ReadByte()) * 256 + [int]$br.ReadByte()
          return [pscustomobject]@{ W = $w; H = $h; Ext = 'jpg'; Mime = 'image/jpeg' }
        }
        if ($marker -eq 0xD8 -or $marker -eq 0xD9 -or ($marker -ge 0xD0 -and $marker -le 0xD7)) { continue }
        $len = ([int]$br.ReadByte()) * 256 + [int]$br.ReadByte()
        $fs.Position = $fs.Position + $len - 2
      }
    }
    throw "unsupported image format (expected PNG or JPEG): $Path"
  } finally { $fs.Dispose() }
}

# Inline-picture paragraph. $rid is supplied by the caller; media is registered as a side effect.
function ImageXml($item, [string]$rid, [int]$docPrId) {
  $file = [string]$item.file
  $path = Join-Path $MediaDir $file
  $info = Get-ImageInfo $path
  $ext  = $info.Ext
  $entryName = 'media/' + [System.IO.Path]::GetFileNameWithoutExtension($file) + '.' + $ext

  $script:mediaEntries[$entryName] = $path
  $script:mediaExts[$ext] = $info.Mime

  $maxH  = 8.4
  $wIn   = if ($item.widthIn) { [double]$item.widthIn } else { 6.2 }
  $hIn   = $wIn * $info.H / $info.W
  if ($hIn -gt $maxH) { $hIn = $maxH; $wIn = $maxH * $info.W / $info.H }

  $cx = [long][math]::Round($wIn * 914400)
  $cy = [long][math]::Round($hIn * 914400)

  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append('<w:p><w:pPr><w:pStyle w:val="Figure"/></w:pPr><w:r><w:drawing>')
  [void]$sb.Append('<wp:inline distT="0" distB="0" distL="0" distR="0">')
  [void]$sb.Append('<wp:extent cx="' + $cx + '" cy="' + $cy + '"/>')
  [void]$sb.Append('<wp:effectExtent l="0" t="0" r="0" b="0"/>')
  [void]$sb.Append('<wp:docPr id="' + $docPrId + '" name="Picture ' + $docPrId + '" descr="' + (Esc $file) + '"/>')
  [void]$sb.Append('<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>')
  [void]$sb.Append('<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">')
  [void]$sb.Append('<pic:pic><pic:nvPicPr><pic:cNvPr id="' + $docPrId + '" name="' + (Esc $file) + '"/><pic:cNvPicPr/></pic:nvPicPr>')
  [void]$sb.Append('<pic:blipFill><a:blip r:embed="' + $rid + '"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>')
  [void]$sb.Append('<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="' + $cx + '" cy="' + $cy + '"/></a:xfrm>')
  [void]$sb.Append('<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>')
  [void]$sb.Append('</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>')

  $xml = $sb.ToString()
  if (-not [string]::IsNullOrWhiteSpace($item.enCaption)) { $xml += (Para 'Caption' $item.enCaption) }
  if (-not [string]::IsNullOrWhiteSpace($item.zhCaption)) { $xml += (Para 'Caption' $item.zhCaption $script:ZhColor) }
  return $xml
}

function TableXml($item) {
  $headers = @($item.headers)
  $rows    = @($item.rows)
  $n       = $headers.Count
  $total   = 9026                                   # A4 usable width in twips

  if ($n -eq 3) { $w = @(3249, 1444, 4333) }
  else {
    $each = [math]::Floor($total / $n)
    $w = @(); for ($i = 0; $i -lt $n - 1; $i++) { $w += $each }
    $w += $total - ($each * ($n - 1))
  }

  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append('<w:tbl><w:tblPr><w:tblW w:w="' + $total + '" w:type="dxa"/>')
  [void]$sb.Append('<w:tblBorders>')
  foreach ($edge in @('top', 'left', 'bottom', 'right', 'insideH', 'insideV')) {
    [void]$sb.Append('<w:' + $edge + ' w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>')
  }
  [void]$sb.Append('</w:tblBorders></w:tblPr><w:tblGrid>')
  foreach ($cw in $w) { [void]$sb.Append('<w:gridCol w:w="' + $cw + '"/>') }
  [void]$sb.Append('</w:tblGrid>')

  [void]$sb.Append('<w:tr><w:trPr><w:tblHeader/></w:trPr>')
  for ($c = 0; $c -lt $n; $c++) {
    [void]$sb.Append('<w:tc><w:tcPr><w:tcW w:w="' + $w[$c] + '" w:type="dxa"/>')
    [void]$sb.Append('<w:shd w:val="clear" w:color="auto" w:fill="EDF2F9"/><w:vAlign w:val="center"/></w:tcPr>')
    [void]$sb.Append((Para 'TableHeader' ([string]$headers[$c])))
    [void]$sb.Append('</w:tc>')
  }
  [void]$sb.Append('</w:tr>')

  foreach ($row in $rows) {
    $cells = @($row)
    [void]$sb.Append('<w:tr>')
    for ($c = 0; $c -lt $n; $c++) {
      $txt = if ($c -lt $cells.Count) { [string]$cells[$c] } else { '' }
      [void]$sb.Append('<w:tc><w:tcPr><w:tcW w:w="' + $w[$c] + '" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>')
      [void]$sb.Append((Para 'TableCell' $txt))
      [void]$sb.Append('</w:tc>')
    }
    [void]$sb.Append('</w:tr>')
  }
  [void]$sb.Append('</w:tbl>')
  return $sb.ToString()
}

# ------------------------------------------------------------------ build ----
$parsed = (Get-Content -LiteralPath $ContentJson -Raw -Encoding UTF8) | ConvertFrom-Json
if ($parsed -is [System.Array]) {
  $items = $parsed
} elseif ($parsed.PSObject.Properties.Name -contains 'items') {
  $items = @($parsed.items)          # allow { "_comment": ..., "items": [ ... ] }
} else {
  throw "content JSON must be a top-level array of items, or an object with an 'items' array"
}
$body = [System.Text.StringBuilder]::new()

$script:mediaEntries = [ordered]@{}    # zip entry name -> disk path
$script:mediaExts    = [ordered]@{}    # ext -> mime
$imageRels           = [ordered]@{}    # rid -> zip entry name
$docPrId             = 0
$ridSeq              = 100

foreach ($it in $items) {
  $zc = $script:ZhColor          # optional Chinese tint; '' = keep style colour
  switch ($it.t) {
    'title'    { [void]$body.Append((Para 'Title'    $it.en)); [void]$body.Append((Para 'TitleZH'  $it.zh $zc)) }
    'subtitle' { [void]$body.Append((Para 'Subtitle' $it.en)); [void]$body.Append((Para 'Subtitle' $it.zh $zc)) }
    'meta'     { [void]$body.Append((Para 'Meta'     $it.en)); [void]$body.Append((Para 'Meta'     $it.zh $zc)) }
    'h2'       { [void]$body.Append((Para 'Heading1' $it.en)); [void]$body.Append((Para 'Heading1' $it.zh $zc)) }
    'h3'       { [void]$body.Append((Para 'Heading2' $it.en)); [void]$body.Append((Para 'Heading2' $it.zh $zc)) }
    'p'        { [void]$body.Append((Para 'Normal'   $it.en)); [void]$body.Append((Para 'Normal'   $it.zh $zc)) }
    'note'     { [void]$body.Append((Para 'Note'     $it.en)); [void]$body.Append((Para 'Note'     $it.zh $zc)) }
    'quote'    {
      foreach ($x in (AsArray $it.en)) { [void]$body.Append((Para 'BQuote' ([string]$x))) }
      foreach ($x in (AsArray $it.zh)) { [void]$body.Append((Para 'BQuote' ([string]$x) $zc)) }
    }
    'bullets'  {
      foreach ($x in (AsArray $it.en)) { [void]$body.Append((Para 'Bullet' ('• ' + [string]$x))) }
      foreach ($x in (AsArray $it.zh)) { [void]$body.Append((Para 'Bullet' ('• ' + [string]$x) $zc)) }
    }
    'table'    { [void]$body.Append((TableXml $it)); [void]$body.Append((SpacerPara)) }
    'image'    {
      $file = [string]$it.file
      $infoTmp = Get-ImageInfo (Join-Path $MediaDir $file)
      $entryName = 'media/' + [System.IO.Path]::GetFileNameWithoutExtension($file) + '.' + $infoTmp.Ext
      if (-not $imageRels.Contains($entryName)) {
        $docPrId++
        $rid = 'rId' + $ridSeq; $ridSeq++
        $imageRels[$rid] = $entryName
        [void]$body.Append((ImageXml $it $rid $docPrId))
      }
    }
    default    { Write-Warning ("unknown item type: " + $it.t) }
  }
}

$sectPr = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>' +
          '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="851" w:footer="992" w:gutter="0"/>' +
          '<w:cols w:space="720"/><w:docGrid w:linePitch="312"/></w:sectPr>'

$documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<w:document' +
  ' xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"' +
  ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"' +
  ' xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"' +
  ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"' +
  ' xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">' +
  '<w:body>' + $body.ToString() + $sectPr + '</w:body></w:document>'

# ---------------------------------------------------------------- styles ----
$CJK = 'Microsoft YaHei'
$stylesXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults><w:rPrDefault><w:rPr>
<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="__CJK__" w:cs="Calibri"/>
<w:sz w:val="22"/><w:szCs w:val="22"/>
</w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="300" w:lineRule="auto"/></w:pPr></w:pPrDefault>
</w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:spacing w:before="0" w:after="80"/></w:pPr>
<w:rPr><w:b/><w:color w:val="1A1A1A"/><w:sz w:val="44"/><w:szCs w:val="44"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="TitleZH"><w:name w:val="Title ZH"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:spacing w:before="0" w:after="200"/></w:pPr>
<w:rPr><w:b/><w:color w:val="2E74B5"/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:spacing w:after="120"/></w:pPr>
<w:rPr><w:i/><w:color w:val="595959"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Meta"><w:name w:val="Meta"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:after="60"/></w:pPr>
<w:rPr><w:color w:val="808080"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
<w:pPr><w:keepNext/><w:spacing w:before="400" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr>
<w:rPr><w:b/><w:color w:val="1F4E79"/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
<w:pPr><w:keepNext/><w:spacing w:before="320" w:after="100"/><w:outlineLvl w:val="1"/></w:pPr>
<w:rPr><w:b/><w:color w:val="2E74B5"/><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Note"><w:name w:val="Note"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="40" w:after="140"/><w:ind w:left="240"/></w:pPr>
<w:rPr><w:i/><w:color w:val="6E6E6E"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="BQuote"><w:name w:val="Bilingual Quote"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="40" w:after="40"/><w:ind w:left="480" w:right="240"/></w:pPr>
<w:rPr><w:color w:val="404040"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Bullet"><w:name w:val="Bilingual Bullet"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="20" w:after="40"/><w:ind w:left="440" w:hanging="220"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Figure"><w:name w:val="Bilingual Figure"/><w:basedOn w:val="Normal"/>
<w:pPr><w:keepNext/><w:spacing w:before="200" w:after="60"/><w:jc w:val="center"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="Bilingual Caption"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="0" w:after="160"/><w:jc w:val="center"/></w:pPr>
<w:rPr><w:i/><w:color w:val="6E6E6E"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="TableCell"><w:name w:val="Table Cell"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="40" w:after="40" w:line="240" w:lineRule="auto"/></w:pPr>
<w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="TableHeader"><w:name w:val="Table Header"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="40" w:after="40" w:line="240" w:lineRule="auto"/></w:pPr>
<w:rPr><w:b/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Spacer"><w:name w:val="Spacer"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>
<w:rPr><w:sz w:val="12"/><w:szCs w:val="12"/></w:rPr></w:style>
</w:styles>
'@.Replace('__CJK__', $CJK)

$imgDefaults = ''
foreach ($ext in $script:mediaExts.Keys) {
  $imgDefaults += '<Default Extension="' + $ext + '" ContentType="' + $script:mediaExts[$ext] + '"/>'
}

$contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
  '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
  '<Default Extension="xml" ContentType="application/xml"/>' + $imgDefaults +
  '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
  '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' +
  '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>' +
  '</Types>'

$rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
  '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
  '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>' +
  '</Relationships>'

$docRelsSb = [System.Text.StringBuilder]::new()
[void]$docRelsSb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
[void]$docRelsSb.Append('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')
[void]$docRelsSb.Append('<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>')
foreach ($rid in $imageRels.Keys) {
  $target = $imageRels[$rid] -replace '^media/', 'media/'
  [void]$docRelsSb.Append('<Relationship Id="' + $rid + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="' + $target + '"/>')
}
[void]$docRelsSb.Append('</Relationships>')
$docRels = $docRelsSb.ToString()

$stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$coreXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
  '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"' +
  ' xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/"' +
  ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
  '<dc:title>Bilingual document (EN/ZH)</dc:title>' +
  '<dc:creator>DeepSeek Harness</dc:creator><cp:lastModifiedBy>DeepSeek Harness</cp:lastModifiedBy>' +
  '<dcterms:created xsi:type="dcterms:W3CDTF">' + $stamp + '</dcterms:created>' +
  '<dcterms:modified xsi:type="dcterms:W3CDTF">' + $stamp + '</dcterms:modified>' +
  '</cp:coreProperties>'

# ------------------------------------------------------------ validation ----
foreach ($pair in @(@('document', $documentXml), @('styles', $stylesXml), @('cts', $contentTypes),
                    @('rootRels', $rootRels), @('docRels', $docRels), @('core', $coreXml))) {
  $partName = $pair[0]
  $xmlText  = $pair[1]
  try { $null = [xml]$xmlText } catch { throw ("XML not well-formed in part '" + $partName + "': " + $_.Exception.Message) }
}
$missing = @()
foreach ($rid in $imageRels.Keys) {
  $t = $imageRels[$rid]
  if (-not $mediaEntries.Contains($t)) { $missing += $t }
}
if ($missing.Count -gt 0) { throw ("image rel targets missing from media map: " + ($missing -join ', ')) }
Write-Host ("XML parts: all well-formed; images: " + $imageRels.Count)

# ----------------------------------------------------------------- write ----
$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
if (Test-Path $OutFile) { Remove-Item $OutFile -Force }

$zip = [System.IO.Compression.ZipFile]::Open($OutFile, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  $parts = [ordered]@{
    '[Content_Types].xml'          = $contentTypes
    '_rels/.rels'                  = $rootRels
    'word/document.xml'            = $documentXml
    'word/styles.xml'              = $stylesXml
    'word/_rels/document.xml.rels' = $docRels
    'docProps/core.xml'            = $coreXml
  }
  foreach ($k in $parts.Keys) {
    $entry  = $zip.CreateEntry($k, [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($parts[$k])
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Dispose()
  }
  foreach ($name in $mediaEntries.Keys) {
    $bytes  = [System.IO.File]::ReadAllBytes($mediaEntries[$name])
    $entry  = $zip.CreateEntry('word/' + $name, [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Dispose()
  }
} finally { $zip.Dispose() }

$fi = Get-Item $OutFile
Write-Host ("Written: {0}" -f $fi.FullName)
Write-Host ("Size:    {0:N0} bytes" -f $fi.Length)

$z = [System.IO.Compression.ZipFile]::OpenRead($OutFile)
$names = $z.Entries | ForEach-Object { $_.FullName }
$z.Dispose()
Write-Host ("Parts:   " + ($names -join ', '))