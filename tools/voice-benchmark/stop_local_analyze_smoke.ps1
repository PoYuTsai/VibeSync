param(
  [Parameter(Mandatory = $true)]
  [string]$ProcessId,
  [Parameter(Mandatory = $true)]
  [string]$RuntimeDir,
  [int]$ProxyPort = 9999,
  [int]$FunctionPort = 8000
)

$ErrorActionPreference = "Stop"

$tempRoot = [System.IO.Path]::GetFullPath(
  [System.IO.Path]::GetTempPath()
).TrimEnd("\")
$fullPath = [System.IO.Path]::GetFullPath($RuntimeDir)
$expectedPrefix = "$tempRoot\vibesync-1-8x-"
if (-not $fullPath.StartsWith(
  $expectedPrefix,
  [System.StringComparison]::OrdinalIgnoreCase
)) {
  throw "Unsafe local smoke temp target: $fullPath"
}

$processIds = $ProcessId.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) |
  ForEach-Object { [int]$_.Trim() }
$processesToStop = @()
foreach ($id in $processIds) {
  $process = Get-Process -Id $id -ErrorAction SilentlyContinue
  if ($process) {
    $details = Get-CimInstance Win32_Process -Filter "ProcessId = $id"
    $commandLine = [string]$details.CommandLine
    if (
      $process.ProcessName -ne "deno" -or
      $commandLine -notmatch "(bench_auth_proxy\.ts|analyze-chat[\\/]index\.ts)"
    ) {
      throw "Refusing to stop unrelated process $id ($($process.ProcessName))"
    }
    $processesToStop += $process
  }
}
foreach ($process in $processesToStop) {
  Stop-Process -Id $process.Id -Force -ErrorAction Stop
  Wait-Process -Id $process.Id -Timeout 5 -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 500

$runtimeExisted = Test-Path -LiteralPath $fullPath -PathType Container
if ($runtimeExisted) {
  Remove-Item -LiteralPath $fullPath -Recurse -Force
}

$listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -in @($ProxyPort, $FunctionPort) }

[ordered]@{
  stoppedProcessIds = $processIds
  removedRuntimeDirectory = $runtimeExisted -and
    -not (Test-Path -LiteralPath $fullPath)
  runtimeDirectoryPresentAfter = Test-Path -LiteralPath $fullPath
  smokePortsListening = @($listening).Count
} | ConvertTo-Json -Compress
