#Requires -Version 5.1
<#
.SYNOPSIS
  Export pack/rules and pack/skills to plain markdown for non-Cursor agents.
.PARAMETER PackRoot
  Pack checkout root. Default: resolved via pack-paths.ps1.
.PARAMETER VerifyOnly
  Exit 1 if on-disk exports differ from what would be generated now.
#>
param(
    [string]$PackRoot = '',
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pack-paths.ps1')

if (-not $PackRoot) {
    $PackRoot = Get-SourceAgentStarterPack
    if (-not $PackRoot) { $PackRoot = Get-CheckoutAgentStarterPack }
}
if (-not $PackRoot -or -not (Test-Path -LiteralPath $PackRoot)) {
    Write-Host 'ERROR: cannot resolve pack root for portable doc sync.'
    exit 1
}
$PackRoot = (Resolve-Path -LiteralPath $PackRoot).Path

function Strip-YamlFrontmatter([string]$Text) {
    if ($Text -match '(?s)^---\r?\n.*?\r?\n---\r?\n(.*)$') {
        return $Matches[1].TrimStart()
    }
    return $Text.TrimStart()
}

function Build-PortableExports([string]$Root) {
    $rulesDir = Join-Path $Root 'pack\rules'
    $skillsDir = Join-Path $Root 'pack\skills'
    $outDir = Join-Path $Root 'pack\docs\portable'
    $skillsOut = Join-Path $outDir 'skills'

    $version = 'unknown'
    $versionPath = Join-Path $Root 'VERSION'
    if (Test-Path -LiteralPath $versionPath) {
        $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
    }

    $ruleFiles = @(Get-ChildItem -LiteralPath $rulesDir -Filter '*.mdc' -File | Sort-Object Name)
    $sections = New-Object System.Collections.ArrayList
    [void]$sections.Add(@(
        '# Generic Agent Starter Pack rules (portable)',
        '',
        'Auto-generated from ``pack/rules/*.mdc``. **Do not edit by hand.**',
        '',
        'Regenerate: ``pack\scripts\sync-portable-docs.ps1`` (also runs during ``sync-audit-system.ps1`` on the pack maintainer repo).',
        '',
        '| Load path | Tool |',
        '|-----------|------|',
        '| ``%USERPROFILE%\.cursor\rules\*.mdc`` | Cursor (after ``install.ps1``) |',
        '| This file | Claude, Copilot, Windsurf, CLI - paste or attach at session start |',
        '',
        "Pack version: $version",
        "Rule files: $($ruleFiles.Count)",
        '',
        '---',
        ''
    ) -join "`r`n")

    foreach ($f in $ruleFiles) {
        $body = Strip-YamlFrontmatter (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8)
        $slug = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        [void]$sections.Add("## $slug`r`n`r`nSource: ``pack/rules/$($f.Name)``$r`n`r`n$body`r`n`r`n---`r`n")
    }
    $genericRules = ($sections -join "`r`n").TrimEnd() + "`r`n"

    $skillExports = @{}
    if (Test-Path -LiteralPath $skillsDir) {
        foreach ($skillDir in Get-ChildItem -LiteralPath $skillsDir -Directory) {
            $skillMd = Join-Path $skillDir.FullName 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillMd)) { continue }
            $body = Strip-YamlFrontmatter (Get-Content -LiteralPath $skillMd -Raw -Encoding UTF8)
            $name = $skillDir.Name
            $header = @(
                "# Skill: $name",
                '',
                "Auto-generated from ``pack/skills/$name/SKILL.md``. **Do not edit by hand.**",
                '',
                "Pack version: $version",
                '',
                '---',
                '',
                $body
            ) -join "`r`n"
            $skillExports[$name] = ($header.TrimEnd() + "`r`n")
        }
    }

    $readme = @(
        '# Portable exports (non-Cursor agents)',
        '',
        'Plain-markdown mirrors of Cursor global rules and skills.',
        '',
        '| File | Purpose |',
        '|------|---------|',
        '| [GENERIC_RULES.md](GENERIC_RULES.md) | All ``pack/rules/*.mdc`` bodies (no YAML frontmatter) |',
        '| [skills/](skills/) | One ``.md`` per pack skill |',
        '',
        '**Cursor users:** ``install.ps1`` installs ``.mdc`` rules automatically - you do not need these files.',
        '',
        '**Other tools:** At session start, attach or paste ``GENERIC_RULES.md``, or the sections you need,',
        'plus this project''s ``AI_INSTRUCTIONS.md`` and ``AGENTS.md``.',
        '',
        'Regenerate after pack rule edits:',
        '',
        '```powershell',
        'pack\scripts\sync-portable-docs.ps1',
        '```',
        '',
        'See also: ``docs/PORTABLE_SETUP.md`` at the pack root.',
        ''
    ) -join "`r`n"

    return [pscustomobject]@{
        GenericRules = $genericRules
        Skills       = $skillExports
        Readme       = $readme
        RuleCount    = $ruleFiles.Count
        OutDir       = $outDir
        SkillsOut    = $skillsOut
    }
}

$built = Build-PortableExports $PackRoot

if ($VerifyOnly) {
    $fail = 0
    $rulesPath = Join-Path $built.OutDir 'GENERIC_RULES.md'
    if (-not (Test-Path -LiteralPath $rulesPath)) {
        Write-Host "[FAIL] missing $rulesPath"
        $fail++
    } else {
        $onDiskRules = Get-Content -LiteralPath $rulesPath -Raw -Encoding UTF8
        if ($onDiskRules -ne $built.GenericRules) {
            Write-Host '[FAIL] GENERIC_RULES.md is stale vs pack/rules (run sync-portable-docs.ps1)'
            $fail++
        } else {
            Write-Host '[OK] GENERIC_RULES.md matches pack/rules'
        }
    }
    foreach ($name in ($built.Skills.Keys | Sort-Object)) {
        $dest = Join-Path $built.SkillsOut "$name.md"
        $expected = $built.Skills[$name]
        if (-not (Test-Path -LiteralPath $dest)) {
            Write-Host "[FAIL] missing skill export: $dest"
            $fail++
        } elseif ((Get-Content -LiteralPath $dest -Raw -Encoding UTF8) -ne $expected) {
            Write-Host "[FAIL] stale skill export: $name.md"
            $fail++
        } else {
            Write-Host "[OK] skill export $name.md"
        }
    }
    $readmePath = Join-Path $built.OutDir 'README.md'
    if (-not (Test-Path -LiteralPath $readmePath)) {
        Write-Host "[FAIL] missing $readmePath"
        $fail++
    }
    if ($fail -gt 0) { exit 1 }
    Write-Host "Portable exports OK ($($built.RuleCount) rules, $($built.Skills.Count) skills)"
    exit 0
}

New-Item -ItemType Directory -Force -Path $built.SkillsOut | Out-Null
Write-Utf8NoBom -Path (Join-Path $built.OutDir 'GENERIC_RULES.md') -Text $built.GenericRules
Write-Utf8NoBom -Path (Join-Path $built.OutDir 'README.md') -Text $built.Readme
foreach ($name in $built.Skills.Keys) {
    Write-Utf8NoBom -Path (Join-Path $built.SkillsOut "$name.md") -Text $built.Skills[$name]
}
Write-Host "[ok] portable exports: $($built.RuleCount) rules, $($built.Skills.Count) skills -> $($built.OutDir)"
exit 0
