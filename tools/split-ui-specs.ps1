<#
.SYNOPSIS
    Splits NotebookLM / Gemini Desktop loop-prompt output into individual
    Markdown files under docs/ui-specs/.

.DESCRIPTION
    Reads text from the Windows clipboard (-FromClipboard) or a file (-InputFile).
    Supports three formats automatically:
      1. Visible markers:  === BEGIN FILE: docs/ui-specs/... ===  ... === END FILE: ... ===
      2. HTML markers:     <!-- BEGIN FILE: docs/ui-specs/... --> ... <!-- END FILE: ... -->
      3. NotebookLM copy fallback (HTML comments stripped): splits on `### UI Spec: <Name>`
         (or `# UI Spec: <Name>`) and routes to `docs/ui-specs/views/<Name>.md` or
         `docs/ui-specs/components/<Name>.md` based on the `**File:**` header line.

    Also restores `mermaid` / `text` code-fence tags stripped by NotebookLM's Copy button,
    strips trailing `LOOP STATUS:` lines, writes UTF-8 without BOM, and prints progress.

.EXAMPLE
    .\tools\split-ui-specs.ps1 -FromClipboard

.EXAMPLE
    .\tools\split-ui-specs.ps1 -InputFile "..\Gemini Notebook Turn 1.md" -DryRun
#>
[CmdletBinding(DefaultParameterSetName = "Clipboard")]
param(
    [Parameter(ParameterSetName = "Clipboard")]
    [switch]$FromClipboard,

    [Parameter(ParameterSetName = "File", Mandatory = $true)]
    [string]$InputFile,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$AllowedRoot = (Join-Path $RepoRoot "docs\ui-specs")

if ($PSCmdlet.ParameterSetName -eq "File") {
    if (-not (Test-Path $InputFile)) {
        throw "InputFile not found: $InputFile"
    }
    $RawText = [System.IO.File]::ReadAllText((Resolve-Path $InputFile).Path, [System.Text.UTF8Encoding]::new($false))
} else {
    $RawText = Get-Clipboard -Raw
    if ([string]::IsNullOrWhiteSpace($RawText)) {
        throw "Clipboard is empty. Copy the NotebookLM / Gemini Desktop response first, or pass -InputFile <path>."
    }
}

function Format-SpecMarkdown {
    param([string]$Body)
    # Remove trailing LOOP STATUS line if present
    $Body = [regex]::Replace($Body, '(?m)^\s*LOOP STATUS:.*$', '').Trim()
    # Normalize NotebookLM shifted heading levels (### UI Spec -> # UI Spec, #### -> ##, ##### -> ###)
    if ($Body -match '(?m)^###\s+UI Spec:') {
        $Body = [regex]::Replace($Body, '(?m)^#####\s+', '### ')
        $Body = [regex]::Replace($Body, '(?m)^####\s+', '## ')
        $Body = [regex]::Replace($Body, '(?m)^###\s+', '# ')
    }
    # Restore ```mermaid language tag stripped by NotebookLM copy button
    $Body = [regex]::Replace($Body, '(?m)^```\r?\n(?=(?:flowchart|graph|sequenceDiagram|stateDiagram|classDiagram|erDiagram)\b)', "``````mermaid`n")
    # Restore ```text on ASCII wireframe blocks
    $Body = [regex]::Replace($Body, '(?m)^```\r?\n(?=\+---)', "``````text`n")
    return ($Body.Trim() + "`n")
}

$Entries = New-Object System.Collections.Generic.List[object]

# 1) Visible markers: === BEGIN FILE: path === ... === END FILE: path ===
#    Tolerate optional leading/trailing whitespace, backticks, or markdown backslash-escapes.
$VisiblePattern = '(?s)[\\`]*={3,}\s*BEGIN FILE:\s*`?([^\r\n=`]+?)`?\s*={3,}[\\`]*[ \t]*\r?\n(.*?)\r?\n[\\`]*={3,}\s*END FILE:\s*[^\r\n=`]+?\s*={3,}[\\`]*'
$Matches = [regex]::Matches($RawText, $VisiblePattern)

# 2) Legacy HTML markers: <!-- BEGIN FILE: path --> ... <!-- END FILE: path -->
if ($Matches.Count -eq 0) {
    $HtmlPattern = '(?s)<!--\s*BEGIN FILE:\s*([^\r\n>]+?)\s*-->[ \t]*\r?\n(.*?)\r?\n<!--\s*END FILE:\s*[^\r\n>]+?\s*-->'
    $Matches = [regex]::Matches($RawText, $HtmlPattern)
}

if ($Matches.Count -gt 0) {
    foreach ($m in $Matches) {
        $Entries.Add([PSCustomObject]@{
            RelPath = $m.Groups[1].Value.Trim().Replace('\', '/')
            Body    = Format-SpecMarkdown $m.Groups[2].Value
        })
    }
} else {
    # 3) Fallback for NotebookLM / Gemini Desktop Copy button:
    #    a) `# Visual & Layout Audit: `items.png`` -> docs/ui-specs/visual-audit/items.md
    $VisPattern = '(?m)^(#{1,3}\s+Visual\s*&\s*Layout\s+Audit:\s*`?([A-Za-z0-9_.-]+?)(?:\.png)?`?.*)$'
    $VMatches = [regex]::Matches($RawText, $VisPattern)
    if ($VMatches.Count -gt 0) {
        for ($i = 0; $i -lt $VMatches.Count; $i++) {
            $start = $VMatches[$i].Index
            $end = if ($i + 1 -lt $VMatches.Count) { $VMatches[$i + 1].Index } else { $RawText.Length }
            $chunk = $RawText.Substring($start, $end - $start)
            $viewName = $VMatches[$i].Groups[2].Value.Trim().ToLowerInvariant() -replace '\.png$', ''
            $Entries.Add([PSCustomObject]@{
                RelPath = "docs/ui-specs/visual-audit/$viewName.md"
                Body    = Format-SpecMarkdown $chunk
            })
        }
    } else {
        # b) `### UI Spec: MainShell` or `# UI Spec: `Button``
        $HeadingPattern = '(?m)^(#{1,3}\s+UI Spec:\s*`?([A-Za-z0-9_.-]+)`?.*)$'
        $HMatches = [regex]::Matches($RawText, $HeadingPattern)
        if ($HMatches.Count -eq 0) {
            throw "No file markers ('=== BEGIN FILE: ... ==='), 'Visual & Layout Audit:', or 'UI Spec: <Name>' headings found in input."
        }

        for ($i = 0; $i -lt $HMatches.Count; $i++) {
            $start = $HMatches[$i].Index
            $end = if ($i + 1 -lt $HMatches.Count) { $HMatches[$i + 1].Index } else { $RawText.Length }
            $chunk = $RawText.Substring($start, $end - $start)
            $specName = $HMatches[$i].Groups[2].Value.Trim() -replace '\.qml$', ''

            # Determine destination folder from **File:** line
            $subDir = "views"
            if ($chunk -match '(?m)\*\*File:\*\*\s*`?app/qml/components/') {
                $subDir = "components"
            } elseif ($chunk -match '(?m)\*\*File:\*\*\s*`?app/qml/(?:views/|main\.qml)') {
                $subDir = "views"
            }

            $Entries.Add([PSCustomObject]@{
                RelPath = "docs/ui-specs/$subDir/$specName.md"
                Body    = Format-SpecMarkdown $chunk
            })
        }
    }
}

$Written = @()
foreach ($entry in $Entries) {
    $RelPath = $entry.RelPath
    $Body = $entry.Body

    # Security guardrail: only write inside docs/ui-specs/
    if ($RelPath -notlike "docs/ui-specs/*" -or $RelPath -match '\.\.') {
        throw "Refusing to write outside docs/ui-specs/: '$RelPath'"
    }

    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $RelPath))
    if (-not $FullPath.StartsWith($AllowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved path escapes docs/ui-specs/: '$FullPath'"
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would write $RelPath ($($Body.Length) chars)" -ForegroundColor Yellow
    } else {
        $Dir = Split-Path -Parent $FullPath
        New-Item -ItemType Directory -Force -Path $Dir | Out-Null
        [System.IO.File]::WriteAllText($FullPath, $Body, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[SAVED] $RelPath ($($Body.Length) chars)" -ForegroundColor Green
    }
    $Written += $RelPath
}

# Print live progress vs total views (11) and components (75)
$ViewSpecs = @(Get-ChildItem -Path (Join-Path $AllowedRoot "views") -Filter "*.md" -ErrorAction SilentlyContinue)
$CompSpecs = @(Get-ChildItem -Path (Join-Path $AllowedRoot "components") -Filter "*.md" -ErrorAction SilentlyContinue)
$VisSpecs  = @(Get-ChildItem -Path (Join-Path $AllowedRoot "visual-audit") -Filter "*.md" -ErrorAction SilentlyContinue)

Write-Host ""
Write-Host "Extracted $($Written.Count) file(s) from this turn." -ForegroundColor Cyan
Write-Host "Current spec progress -> Views: $($ViewSpecs.Count)/11 | Components: $($CompSpecs.Count)/75 | Visual Audits: $($VisSpecs.Count)/9" -ForegroundColor Cyan
