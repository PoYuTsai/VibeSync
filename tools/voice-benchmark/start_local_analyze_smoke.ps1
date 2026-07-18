param(
  [int]$ProxyPort = 9999,
  [int]$FunctionPort = 8000
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

function Import-DotEnv([string]$Path) {
  foreach ($raw in Get-Content -LiteralPath $Path -Encoding utf8) {
    $line = $raw.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }
    if ($line.StartsWith("export ")) { $line = $line.Substring(7).Trim() }
    $separator = $line.IndexOf("=")
    if ($separator -le 0) { continue }
    $key = $line.Substring(0, $separator).Trim()
    $value = $line.Substring($separator + 1).Trim()
    if (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    ) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    Set-Item -Path "Env:$key" -Value $value
  }
}

$busyPorts = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -in @($ProxyPort, $FunctionPort) }
if ($busyPorts) {
  throw "Local smoke port already in use: $($busyPorts.LocalPort -join ', ')"
}

Import-DotEnv (Join-Path $repoRoot ".env.local")
$productionUrl = $env:SUPABASE_URL
$anonKey = $env:SUPABASE_ANON_KEY
Import-DotEnv (Join-Path $repoRoot "supabase/.env")
Import-DotEnv (Join-Path $repoRoot "tools/ocr-golden/.env.golden")

$authBody = @{
  email = $env:TEST_EMAIL
  password = $env:TEST_PASSWORD
} | ConvertTo-Json -Compress
$auth = Invoke-RestMethod `
  -Method Post `
  -Uri "$productionUrl/auth/v1/token?grant_type=password" `
  -Headers @{ apikey = $anonKey } `
  -ContentType "application/json" `
  -Body $authBody
if (-not $auth.access_token) {
  throw "Test-account authentication returned no token"
}

$runtimeDir = Join-Path (
  [System.IO.Path]::GetTempPath()
) ("vibesync-1-8x-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $runtimeDir | Out-Null
$tokenPath = Join-Path $runtimeDir "token.env"
[System.IO.File]::WriteAllText(
  $tokenPath,
  "OCR_GOLDEN_TOKEN=$($auth.access_token)",
  [System.Text.UTF8Encoding]::new($false)
)

$deno = (Get-Command deno).Source
$env:SUPABASE_URL = $productionUrl
$env:OCR_BENCH_TOKEN_FILE = $tokenPath
$env:MOCK_ANALYSIS_RUNS = "1"
$env:PORT = "$ProxyPort"
$proxy = $null
$function = $null
try {
  $proxy = Start-Process `
    -FilePath $deno `
    -ArgumentList @(
      "run", "--allow-net", "--allow-read", "--allow-env",
      "tools/ocr-golden/bench_auth_proxy.ts"
    ) `
    -WorkingDirectory $repoRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $runtimeDir "proxy.out.log") `
    -RedirectStandardError (Join-Path $runtimeDir "proxy.err.log") `
    -PassThru

  $env:SUPABASE_URL = "http://127.0.0.1:$ProxyPort"
  $env:SUPABASE_SERVICE_ROLE_KEY = $anonKey
  $env:STREAM_ANALYZE_ENABLED = "true"
  $env:PORT = "$FunctionPort"
  $function = Start-Process `
    -FilePath $deno `
    -ArgumentList @(
      "run", "--allow-net", "--allow-env", "--allow-read",
      "supabase/functions/analyze-chat/index.ts"
    ) `
    -WorkingDirectory $repoRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $runtimeDir "function.out.log") `
    -RedirectStandardError (Join-Path $runtimeDir "function.err.log") `
    -PassThru
} catch {
  foreach ($started in @($proxy, $function)) {
    if ($started -and -not $started.HasExited) {
      Stop-Process -Id $started.Id -Force -ErrorAction SilentlyContinue
    }
  }
  Remove-Item -LiteralPath $runtimeDir -Recurse -Force -ErrorAction SilentlyContinue
  throw
}

function Test-LocalPort([int]$Port) {
  try {
    $client = [System.Net.Sockets.TcpClient]::new()
    $task = $client.ConnectAsync("127.0.0.1", $Port)
    if (-not $task.Wait(500)) {
      $client.Dispose()
      return $false
    }
    $connected = $client.Connected
    $client.Dispose()
    return $connected
  } catch {
    return $false
  }
}

$deadline = (Get-Date).AddSeconds(30)
do {
  Start-Sleep -Milliseconds 300
  $proxyReady = Test-LocalPort $ProxyPort
  $functionReady = Test-LocalPort $FunctionPort
  if ($proxy.HasExited -or $function.HasExited) { break }
} until (($proxyReady -and $functionReady) -or (Get-Date) -ge $deadline)

$result = [ordered]@{
  runtimeDir = $runtimeDir
  proxyPid = $proxy.Id
  functionPid = $function.Id
  proxyPort = $ProxyPort
  functionPort = $FunctionPort
  proxyReady = $proxyReady
  functionReady = $functionReady
  proxyExited = $proxy.HasExited
  functionExited = $function.HasExited
}
$result | ConvertTo-Json -Compress

if (-not ($proxyReady -and $functionReady)) {
  Get-Content (Join-Path $runtimeDir "proxy.err.log") -Encoding utf8 `
    -ErrorAction SilentlyContinue | Select-Object -Last 30
  Get-Content (Join-Path $runtimeDir "function.err.log") -Encoding utf8 `
    -ErrorAction SilentlyContinue | Select-Object -Last 30
  if (-not $proxy.HasExited) { Stop-Process -Id $proxy.Id }
  if (-not $function.HasExited) { Stop-Process -Id $function.Id }
  Remove-Item -LiteralPath $runtimeDir -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}
