# Shared Agent Starter Pack path resolution (supports legacy Cursor-era names/paths).
function Get-AgentStarterPackCandidates {
    $list = @()
    if ($env:AGENT_STARTER_PACK_ROOT) { $list += $env:AGENT_STARTER_PACK_ROOT }
    if ($env:CURSOR_STARTER_PACK_ROOT) { $list += $env:CURSOR_STARTER_PACK_ROOT }
    $list += Join-Path $env:USERPROFILE '.cursor\AgentStarterPack'
    $list += Join-Path $env:USERPROFILE '.cursor\agent-starter-pack'
    $list += Join-Path $env:USERPROFILE 'OneDrive\Desktop\AgentStarterPack'
    $list += Join-Path $env:USERPROFILE 'OneDrive\Desktop\CursorAgentStarterPack'
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ($desktop) {
        $list += Join-Path $desktop 'AgentStarterPack'
        $list += Join-Path $desktop 'CursorAgentStarterPack'
    }
    return $list | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique
}

function Get-AgentStarterPackRoot {
    foreach ($base in (Get-AgentStarterPackCandidates)) {
        $manifest = Join-Path $base 'pack\audit\manifest.json'
        if (Test-Path -LiteralPath $manifest) { return $base }
    }
    return $null
}

function Get-DesktopAgentStarterPack {
    foreach ($base in (Get-AgentStarterPackCandidates)) {
        if ($base -match 'AgentStarterPack|CursorAgentStarterPack') {
            if (Test-Path -LiteralPath (Join-Path $base 'install.ps1')) { return $base }
        }
    }
    return $null
}

function Get-InstalledAgentStarterPack {
    $preferred = Join-Path $env:USERPROFILE '.cursor\AgentStarterPack'
    if (Test-Path -LiteralPath (Join-Path $preferred 'pack\audit\manifest.json')) { return $preferred }
    $legacy = Join-Path $env:USERPROFILE '.cursor\agent-starter-pack'
    if (Test-Path -LiteralPath (Join-Path $legacy 'pack\audit\manifest.json')) { return $legacy }
    return $preferred
}
