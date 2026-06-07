param(
  [string]$RevenueCatApiKey = $env:REVENUECAT_IOS_API_KEY,
  [string]$SubscriberId = "vibesync-preflight-smoke",
  [string]$ApiBaseUrl = "https://api.revenuecat.com/v1",
  [int]$TimeoutSeconds = 15
)

$ErrorActionPreference = "Stop"

function Fail-SmokeCheck {
  param([string]$Message)

  Write-Host "RevenueCat secret smoke failed: $Message"
  exit 1
}

if ([string]::IsNullOrWhiteSpace($RevenueCatApiKey)) {
  Fail-SmokeCheck "REVENUECAT_IOS_API_KEY is not available to the workflow."
}

$trimmedKey = $RevenueCatApiKey.Trim()
if ($trimmedKey.StartsWith("appl_", [System.StringComparison]::OrdinalIgnoreCase)) {
  Fail-SmokeCheck "REVENUECAT_IOS_API_KEY is a public SDK key; Edge Functions require the secret server key."
}

if ([string]::IsNullOrWhiteSpace($SubscriberId)) {
  Fail-SmokeCheck "SubscriberId is required."
}

$encodedSubscriberId = [System.Uri]::EscapeDataString($SubscriberId.Trim())
$base = $ApiBaseUrl.TrimEnd("/")
$url = "$base/subscribers/$encodedSubscriberId"

Write-Host "Checking RevenueCat server API key against /v1/subscribers/<redacted>..."

try {
  $response = Invoke-WebRequest `
    -Uri $url `
    -Method Get `
    -Headers @{
      Authorization = "Bearer $trimmedKey"
      "Content-Type" = "application/json"
    } `
    -TimeoutSec $TimeoutSeconds `
    -ErrorAction Stop

  if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
    Fail-SmokeCheck "RevenueCat returned HTTP $($response.StatusCode)."
  }

  $payload = $response.Content | ConvertFrom-Json -ErrorAction Stop
  if ($null -eq $payload.subscriber) {
    Fail-SmokeCheck "RevenueCat response did not include subscriber data."
  }
} catch {
  $statusCode = $null
  if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
    $statusCode = [int]$_.Exception.Response.StatusCode
  }

  if ($statusCode -eq 401 -or $statusCode -eq 403) {
    Fail-SmokeCheck "RevenueCat rejected the server key (HTTP $statusCode)."
  }

  if ($statusCode) {
    Fail-SmokeCheck "RevenueCat request failed with HTTP $statusCode."
  }

  Fail-SmokeCheck "RevenueCat request failed before a valid response."
}

Write-Host "RevenueCat secret smoke passed."
