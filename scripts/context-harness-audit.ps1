param(
  [int]$RootWarnBytes = 4096,
  [int]$SkillWarnCount = 8
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$HomeClaude = Join-Path $HOME '.claude'

function Get-LineCount {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  return (Get-Content -LiteralPath $Path | Measure-Object -Line).Lines
}

function Get-DirStats {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return [PSCustomObject]@{ Count = 0; Bytes = 0 }
  }

  $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue
  $measure = $files | Measure-Object -Property Length -Sum
  $sum = 0
  if ($null -ne $measure.Sum) {
    $sum = [int64]$measure.Sum
  }

  return [PSCustomObject]@{
    Count = ($files | Measure-Object).Count
    Bytes = $sum
  }
}

function Read-JsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  } catch {
    return [PSCustomObject]@{ _parseError = $_.Exception.Message }
  }
}

function Get-EnabledPluginRows {
  param(
    [string]$Scope,
    [string]$Path
  )

  $json = Read-JsonFile $Path
  if ($null -eq $json -or $null -eq $json.enabledPlugins) {
    return @()
  }

  return $json.enabledPlugins.PSObject.Properties | ForEach-Object {
    [PSCustomObject]@{
      Scope = $Scope
      Plugin = $_.Name
      Enabled = $_.Value
    }
  }
}

function Get-McpCount {
  param([string]$Path)
  $json = Read-JsonFile $Path
  if ($null -eq $json -or $null -eq $json.mcpServers) { return 0 }
  return ($json.mcpServers.PSObject.Properties | Measure-Object).Count
}

function Get-RelativePath {
  param([string]$Path)
  return [System.IO.Path]::GetRelativePath($RepoRoot, $Path)
}

Write-Host '== Root context files =='
$rootFiles = 'CLAUDE.md', 'AGENTS.md', 'MEMORY.md'
$rootRows = foreach ($name in $rootFiles) {
  $path = Join-Path $RepoRoot $name
  if (Test-Path -LiteralPath $path) {
    $item = Get-Item -LiteralPath $path
    [PSCustomObject]@{
      File = $name
      Bytes = $item.Length
      Lines = Get-LineCount $path
      Status = $(if ($item.Length -gt $RootWarnBytes) { 'WARN' } else { 'OK' })
    }
  } else {
    [PSCustomObject]@{ File = $name; Bytes = 0; Lines = 0; Status = 'MISSING' }
  }
}
$rootRows | Format-Table -AutoSize

Write-Host ''
Write-Host '== Project skills =='
$skillsPath = Join-Path $RepoRoot '.claude/skills'
$activeSkillDirs = @()
if (Test-Path -LiteralPath $skillsPath) {
  $activeSkillDirs = Get-ChildItem -LiteralPath $skillsPath -Directory -Force
}
$activeSkillBytes = 0
foreach ($dir in $activeSkillDirs) {
  $activeSkillBytes += (Get-DirStats $dir.FullName).Bytes
}
[PSCustomObject]@{
  ActiveSkillCount = $activeSkillDirs.Count
  ActiveSkillBytes = $activeSkillBytes
  Status = $(if ($activeSkillDirs.Count -gt $SkillWarnCount) { 'WARN' } else { 'OK' })
} | Format-Table -AutoSize

$disabledPath = Join-Path $RepoRoot '.claude/skills.disabled'
$disabledStats = Get-DirStats $disabledPath
[PSCustomObject]@{
  DisabledSkillFiles = $disabledStats.Count
  DisabledSkillBytes = $disabledStats.Bytes
} | Format-Table -AutoSize

Write-Host ''
Write-Host '== Slash command injection scan =='
$commandsPath = Join-Path $RepoRoot '.claude/commands'
$findings = @()
if (Test-Path -LiteralPath $commandsPath) {
  $commandFiles = Get-ChildItem -LiteralPath $commandsPath -Recurse -File -Force
  foreach ($file in $commandFiles) {
    $matches = Select-String -LiteralPath $file.FullName -Pattern '[@!]' -ErrorAction SilentlyContinue
    foreach ($match in $matches) {
      $findings += [PSCustomObject]@{
        File = Get-RelativePath $file.FullName
        Line = $match.LineNumber
        Text = $match.Line.Trim()
      }
    }
  }
}

if ($findings.Count -eq 0) {
  Write-Host 'OK: no project slash command contains injection markers.'
} else {
  $findings | Format-Table -AutoSize
}

Write-Host ''
Write-Host '== Enabled plugins =='
$pluginRows = @()
$pluginRows += Get-EnabledPluginRows 'project' (Join-Path $RepoRoot '.claude/settings.local.json')
$pluginRows += Get-EnabledPluginRows 'global' (Join-Path $HomeClaude 'settings.json')
if ($pluginRows.Count -eq 0) {
  Write-Host 'No enabledPlugins found.'
} else {
  $pluginRows | Format-Table -AutoSize
}

Write-Host ''
Write-Host '== MCP server counts =='
[PSCustomObject]@{
  ProjectMcpServers = Get-McpCount (Join-Path $RepoRoot '.mcp.json')
  GlobalMcpServers = Get-McpCount (Join-Path $HomeClaude 'settings.json')
} | Format-Table -AutoSize

Write-Host ''
Write-Host '== Global context hints =='
$globalClaude = Join-Path $HomeClaude 'CLAUDE.md'
if (Test-Path -LiteralPath $globalClaude) {
  $item = Get-Item -LiteralPath $globalClaude
  [PSCustomObject]@{
    File = $globalClaude
    Bytes = $item.Length
    Lines = Get-LineCount $globalClaude
  } | Format-Table -AutoSize
} else {
  Write-Host 'No global CLAUDE.md found.'
}

$globalSkillStats = Get-DirStats (Join-Path $HomeClaude 'skills')
[PSCustomObject]@{
  GlobalSkillFiles = $globalSkillStats.Count
  GlobalSkillBytes = $globalSkillStats.Bytes
} | Format-Table -AutoSize
