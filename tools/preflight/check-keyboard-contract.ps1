param(
  [string]$Endpoint = "https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/keyboard-reply",
  [string]$ExpectedVersion = "keyboard-reply-exactly-once-v1",
  [string]$AnonKey = $env:SUPABASE_PROD_ANON_KEY
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AnonKey)) {
  throw "Keyboard contract health check requires SUPABASE_PROD_ANON_KEY."
}

$headers = @{
  apikey = $AnonKey
  Authorization = "Bearer $AnonKey"
}

try {
  $response = Invoke-RestMethod -Uri $Endpoint -Method Get -Headers $headers -TimeoutSec 20
} catch {
  throw "Keyboard contract health check failed: endpoint unavailable."
}

if (
  $response.status -ne "ok" -or
  $response.function -ne "keyboard-reply" -or
  $response.contractVersion -ne $ExpectedVersion
) {
  throw "Keyboard contract health check failed: expected $ExpectedVersion."
}

Write-Host "Keyboard contract preflight passed: $ExpectedVersion"
