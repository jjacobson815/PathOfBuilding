<#
.SYNOPSIS
    Packages PoB Qt/QML views, components, Lua bridges, and reference docs into
    domain-grouped Markdown packs via Repomix for Gemini Desktop & NotebookLM.

.DESCRIPTION
    Groups all 86 QML files (+ StatDiff.js), their matching Lua bridge modules,
    key C++ helpers, and port-plan reference docs into 8 self-contained Markdown
    packs under docs/repomix-packs/ (gitignored).

    Also validates 100% coverage of app/qml/ so no QML file is silently omitted,
    and optionally copies the 9 baseline PNG screenshots alongside the packs for
    visual critique in Gemini Desktop / NotebookLM.

.EXAMPLE
    .\tools\repomix-ui-docs.ps1
    Builds all 8 packs using `npx repomix` and copies baseline screenshots.

.EXAMPLE
    .\tools\repomix-ui-docs.ps1 -Pack 02-view-buildlist-import,01-core-components
    Builds only the two specified packs.

.EXAMPLE
    .\tools\repomix-ui-docs.ps1 -PureMarkdown
    Skips npx/repomix and concatenates Markdown directly in PowerShell (offline / instant).
#>
[CmdletBinding()]
param(
    [string[]]$Pack = @("all"),
    [string]$OutputDir = "docs/repomix-packs",
    [switch]$IncludeScreenshots = $true,
    [switch]$PureMarkdown,
    [switch]$SkipCoverageCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $RepoRoot

try {
    $PackDefs = [ordered]@{
        "00-shell-and-theme" = @{
            Title       = "App Shell, Chrome, Theme, TextMetrics & Global Popups"
            Screenshots = @("list.png", "tree.png")
            Files       = @(
                "app/qml/main.qml"
                "app/qml/components/TopBar.qml"
                "app/qml/components/BottomBar.qml"
                "app/qml/components/StatPanel.qml"
                "app/qml/components/StatDiff.js"
                "app/qml/components/MainSkillPanel.qml"
                "app/qml/components/WarningsBar.qml"
                "app/qml/components/UpdateBanner.qml"
                "app/qml/components/Toast.qml"
                "app/qml/components/ToastStack.qml"
                "app/qml/components/AboutPopup.qml"
                "app/qml/components/OptionsDialog.qml"
                "app/qml/components/SaveAsPopup.qml"
                "app/qml/components/ConversionPopup.qml"
                "app/qml/components/LoadoutManagePopup.qml"
                "app/src/Theme.h"
                "app/src/Theme.cpp"
                "app/src/TextMetrics.h"
                "app/src/TextMetrics.cpp"
                "app/src/ColorText.h"
                "app/src/ColorText.cpp"
                "app/lua/pob_shell.lua"
                "app/lua/pob_update.lua"
                "port-plan/reference/control-library.md"
                "port-plan/reference/tabs-catalog.md"
                "port-plan/reference/text-rendering.md"
            )
        }
        "01-core-components" = @{
            Title       = "Reusable Core UI Primitives, Input, Drag-Drop & Base Popups"
            Screenshots = @("import.png", "items.png", "skills.png")
            Files       = @(
                "app/qml/components/Arrow.qml"
                "app/qml/components/Button.qml"
                "app/qml/components/CheckBox.qml"
                "app/qml/components/CheckMark.qml"
                "app/qml/components/Chrome.qml"
                "app/qml/components/ColorText.qml"
                "app/qml/components/ConfirmPopup.qml"
                "app/qml/components/Dragger.qml"
                "app/qml/components/DragGhost.qml"
                "app/qml/components/DragSource.qml"
                "app/qml/components/DropDownControl.qml"
                "app/qml/components/DropTarget.qml"
                "app/qml/components/EditControl.qml"
                "app/qml/components/HoverKeyArea.qml"
                "app/qml/components/Label.qml"
                "app/qml/components/MessagePopup.qml"
                "app/qml/components/NewFolderPopup.qml"
                "app/qml/components/PathControl.qml"
                "app/qml/components/PopupBase.qml"
                "app/qml/components/PopupButton.qml"
                "app/qml/components/RectangleOutline.qml"
                "app/qml/components/ScrollBar.qml"
                "app/qml/components/SearchHost.qml"
                "app/qml/components/Section.qml"
                "app/qml/components/SetManagePopup.qml"
                "app/qml/components/Slider.qml"
                "app/qml/components/TextInputPopup.qml"
                "app/qml/components/TextListControl.qml"
                "app/qml/components/Tooltip.qml"
                "app/qml/components/UndoHandler.qml"
                "port-plan/reference/control-library.md"
                "port-plan/reference/text-rendering.md"
            )
        }
        "02-view-buildlist-import" = @{
            Title       = "Build List Page & Import/Export Tab"
            Screenshots = @("list.png", "import.png")
            Files       = @(
                "app/qml/views/BuildListPage.qml"
                "app/qml/views/ImportView.qml"
                "app/qml/views/PlaceholderView.qml"
                "app/lua/pob_import.lua"
                "app/lua/pob_network.lua"
                "app/src/BuildListModel.h"
                "app/src/BuildListModel.cpp"
                "port-plan/phases/PHASE-11-import-export.md"
            )
        }
        "03-view-tree" = @{
            Title       = "Passive Tree Tab, Viewer & Tree Popups"
            Screenshots = @("tree.png")
            Files       = @(
                "app/qml/views/TreeView.qml"
                "app/qml/components/TreeViewer.qml"
                "app/qml/components/SpecManagePopup.qml"
                "app/qml/components/TreeImportPopup.qml"
                "app/qml/components/TreeExportPopup.qml"
                "app/qml/components/MasteryPopup.qml"
                "app/qml/components/TattooPopup.qml"
                "app/qml/components/TimelessJewelPopup.qml"
                "app/qml/components/PowerReportPanel.qml"
                "app/lua/pob_timeless.lua"
                "app/src/TreeViewController.h"
                "app/src/TreeViewController.cpp"
                "port-plan/phases/PHASE-4-tree-tab.md"
            )
        }
        "04-view-skills" = @{
            Title       = "Skills Tab, GemSelect, Socket Groups & Spectre Library"
            Screenshots = @("skills.png")
            Files       = @(
                "app/qml/views/SkillsView.qml"
                "app/qml/components/SocketGroupList.qml"
                "app/qml/components/GemSelect.qml"
                "app/qml/components/SpectreLibraryPopup.qml"
                "app/lua/pob_skills.lua"
                "port-plan/phases/PHASE-5-skills-tab.md"
            )
        }
        "05-view-items" = @{
            Title       = "Items Tab, Item Editor, Item DB & Crafting Popups"
            Screenshots = @("items.png")
            Files       = @(
                "app/qml/views/ItemsView.qml"
                "app/qml/components/ItemAffixRow.qml"
                "app/qml/components/ItemDBPanel.qml"
                "app/qml/components/ItemListBox.qml"
                "app/qml/components/ItemTextPopup.qml"
                "app/qml/components/CraftAnointPopup.qml"
                "app/qml/components/CraftButton.qml"
                "app/qml/components/CraftCorruptPopup.qml"
                "app/qml/components/CraftCruciblePopup.qml"
                "app/qml/components/CraftCustomPopup.qml"
                "app/qml/components/CraftDrop.qml"
                "app/qml/components/CraftEdit.qml"
                "app/qml/components/CraftEnchantPopup.qml"
                "app/qml/components/CraftImplicitPopup.qml"
                "app/qml/components/CraftLabel.qml"
                "app/qml/components/CraftNewPopup.qml"
                "app/qml/components/CraftPopupBase.qml"
                "app/lua/pob_items.lua"
                "port-plan/phases/PHASE-6-items-tab.md"
            )
        }
        "06-view-config-calcs" = @{
            Title       = "Configuration & Calculations Tabs"
            Screenshots = @("config.png", "calcs.png")
            Files       = @(
                "app/qml/views/ConfigView.qml"
                "app/qml/components/ConfigOptionRow.qml"
                "app/qml/views/CalcsView.qml"
                "app/qml/components/CalcSectionCard.qml"
                "app/qml/components/CalcBreakdownPanel.qml"
                "app/qml/components/CalcRadiusVisual.qml"
                "app/lua/pob_config.lua"
                "app/lua/pob_calcs.lua"
                "port-plan/phases/PHASE-7-config-tab.md"
                "port-plan/phases/PHASE-8-calcs-tab.md"
            )
        }
        "07-view-notes-party" = @{
            Title       = "Notes & Party Tabs"
            Screenshots = @("notes.png", "party.png")
            Files       = @(
                "app/qml/views/NotesView.qml"
                "app/qml/views/PartyView.qml"
                "app/qml/components/PartyBufferBox.qml"
                "app/lua/pob_notes_party.lua"
                "port-plan/phases/PHASE-9-notes-party.md"
            )
        }
    }

    # --- 1. Validate 100% coverage of app/qml/**/*.qml and *.js ---
    if (-not $SkipCoverageCheck) {
        $AllQmlFiles = Get-ChildItem -Path "app/qml" -Recurse -File |
            Where-Object { $_.Extension -in @(".qml", ".js") } |
            ForEach-Object { $_.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/') } |
            Sort-Object

        $MappedQml = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($key in $PackDefs.Keys) {
            foreach ($f in $PackDefs[$key].Files) {
                if ($f -like "app/qml/*") {
                    [void]$MappedQml.Add($f)
                }
            }
        }

        $Missing = @($AllQmlFiles | Where-Object { -not $MappedQml.Contains($_) })
        if ($Missing.Count -gt 0) {
            throw "Unmapped app/qml files detected! Add them to `$PackDefs in tools/repomix-ui-docs.ps1:`n - " + ($Missing -join "`n - ")
        }
        Write-Host "[OK] QML coverage verified: $($AllQmlFiles.Count)/$($AllQmlFiles.Count) files in app/qml/ mapped across $($PackDefs.Count) packs." -ForegroundColor Green
    }

    # --- 2. Resolve selected packs ---
    $SelectedPacks = if ($Pack -contains "all") {
        @($PackDefs.Keys)
    } else {
        foreach ($p in $Pack) {
            if (-not $PackDefs.Contains($p)) {
                throw "Unknown pack '$p'. Valid packs: $($PackDefs.Keys -join ', ')"
            }
        }
        $Pack
    }

    # --- 3. Check Repomix availability ---
    $UseRepomixCli = -not $PureMarkdown
    if ($UseRepomixCli) {
        $npxCmd = Get-Command npx -ErrorAction SilentlyContinue
        if (-not $npxCmd) {
            Write-Warning "npx not found on PATH; falling back to -PureMarkdown mode."
            $UseRepomixCli = $false
        }
    }

    $OutRoot = Join-Path $RepoRoot $OutputDir
    New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

    $Summary = @()

    function Write-PureMarkdownPack {
        param([string]$PackKey, [hashtable]$Def, [string]$OutPath)
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("# PoB-Qt UI Pack: $PackKey - $($Def.Title)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        [void]$sb.AppendLine("Files included: $($Def.Files.Count)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## File Index")
        foreach ($rel in $Def.Files) {
            [void]$sb.AppendLine("- ``$rel``")
        }
        [void]$sb.AppendLine("")

        foreach ($rel in $Def.Files) {
            $abs = Join-Path $RepoRoot $rel
            if (-not (Test-Path $abs)) {
                throw "Missing source file in pack '$PackKey': $rel"
            }
            $ext = [System.IO.Path]::GetExtension($rel).TrimStart('.').ToLowerInvariant()
            $lang = switch ($ext) {
                "qml" { "qml" }
                "js"  { "javascript" }
                "lua" { "lua" }
                "cpp" { "cpp" }
                "h"   { "cpp" }
                "md"  { "markdown" }
                default { "" }
            }
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("## File: ``$rel``")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine(('``````' + $lang))
            $raw = [System.IO.File]::ReadAllText($abs, [System.Text.UTF8Encoding]::new($false))
            [void]$sb.AppendLine($raw.TrimEnd("`r", "`n"))
            [void]$sb.AppendLine('``````')
            [void]$sb.AppendLine("")
        }
        [System.IO.File]::WriteAllText($OutPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
    }

    # --- 4. Build each pack ---
    foreach ($packKey in $SelectedPacks) {
        $def = $PackDefs[$packKey]
        $outFile = Join-Path $OutRoot "$packKey.md"

        # Verify all files exist before invoking repomix
        foreach ($rel in $def.Files) {
            if (-not (Test-Path (Join-Path $RepoRoot $rel))) {
                throw "Missing file '$rel' in pack '$packKey'."
            }
        }

        Write-Host "Packing $packKey ($($def.Files.Count) files)..." -ForegroundColor Cyan

        if ($UseRepomixCli) {
            $includeArg = ($def.Files -join ",")
            $repomixArgs = @(
                "--yes", "repomix",
                "--style", "markdown",
                "--include", $includeArg,
                "--no-file-summary",
                "--output", $outFile
            )
            & npx @repomixArgs
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outFile)) {
                throw "repomix failed for pack '$packKey' (exit code $LASTEXITCODE)."
            }
        } else {
            Write-PureMarkdownPack -PackKey $packKey -Def $def -OutPath $outFile
        }

        $info = Get-Item $outFile
        $text = [System.IO.File]::ReadAllText($outFile, [System.Text.UTF8Encoding]::new($false))
        $words = ($text -split '\s+').Count
        $estTokens = [math]::Round($text.Length / 4.0)
        $status = if ($words -lt 400000) { "OK (NotebookLM)" } else { "LARGE (>400k words)" }

        $Summary += [PSCustomObject]@{
            Pack        = "$packKey.md"
            Files       = $def.Files.Count
            SizeKB      = [math]::Round($info.Length / 1KB, 1)
            Words       = $words
            EstTokens   = $estTokens
            Status      = $status
            Screenshots = ($def.Screenshots -join ", ")
        }
    }

    # --- 5. Copy baseline screenshots alongside packs ---
    $ShotOut = Join-Path $OutRoot "screenshots"
    if ($IncludeScreenshots -and (Test-Path "app/tests/capture-baseline")) {
        New-Item -ItemType Directory -Force -Path $ShotOut | Out-Null
        Copy-Item "app/tests/capture-baseline/*.png" -Destination $ShotOut -Force
        Write-Host "[OK] Copied baseline screenshots -> $OutputDir/screenshots/" -ForegroundColor Green
    }

    # --- 6. Emit upload guide inside output directory ---
    $GuidePath = Join-Path $OutRoot "README-UPLOAD.md"
    $guide = New-Object System.Text.StringBuilder
    [void]$guide.AppendLine("# Repomix UI Packs for NotebookLM & Gemini Desktop")
    [void]$guide.AppendLine("")
    [void]$guide.AppendLine("Upload these Markdown files directly as sources in **NotebookLM** or attach a pack + its matching screenshot(s) in **Gemini Desktop**.")
    [void]$guide.AppendLine("Use the prompts in ``docs/ui-specs/PROMPTS.md`` and the template in ``docs/ui-specs/SPEC-TEMPLATE.md``.")
    [void]$guide.AppendLine("")
    [void]$guide.AppendLine("| Pack | Files | Size (KB) | Est. Tokens | Companion Screenshots |")
    [void]$guide.AppendLine("| :--- | ---: | ---: | ---: | :--- |")
    foreach ($row in $Summary) {
        [void]$guide.AppendLine("| ``$($row.Pack)`` | $($row.Files) | $($row.SizeKB) | $($row.EstTokens) | $($row.Screenshots) |")
    }
    [System.IO.File]::WriteAllText($GuidePath, $guide.ToString(), [System.Text.UTF8Encoding]::new($false))

    Write-Host ""
    $Summary | Format-Table -AutoSize
    Write-Host "Output directory: $OutRoot" -ForegroundColor Green
    Write-Host "Next step: Open docs/ui-specs/PROMPTS.md and upload the packs above to NotebookLM or Gemini Desktop." -ForegroundColor Yellow
}
finally {
    Pop-Location
}
