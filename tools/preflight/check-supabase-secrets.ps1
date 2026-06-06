param(
  [string]$ProjectRef = "fcmwrmwdoqiqdnbisdpg",
  [string[]]$RequiredSecrets = @(
    "CLAUDE_API_KEY",
    "REVENUECAT_IOS_API_KEY",
    "REVENUECAT_WEBHOOK_SECRET"
  )
)

$ErrorActionPreference = "Stop"

function Invoke-SupabaseSecretsList {
  param([string]$ProjectRef)

  $supabase = Get-Command supabase -ErrorAction SilentlyContinue
  if ($supabase) {
    return & supabase secrets list --project-ref $ProjectRef 2>&1
  }

  $npxCmd = Get-Command npx.cmd -ErrorAction SilentlyContinue
  if ($npxCmd) {
    return & npx.cmd --yes supabase secrets list --project-ref $ProjectRef 2>&1
  }

  $npx = Get-Command npx -ErrorAction SilentlyContinue
  if ($npx) {
    return & npx --yes supabase secrets list --project-ref $ProjectRef 2>&1
  }

  throw "Supabase CLI is unavailable. Install supabase CLI or Node.js/npx."
}

Write-Host "Checking Supabase Edge Function secrets for project $ProjectRef..."

$output = Invoke-SupabaseSecretsList -ProjectRef $ProjectRef
if ($LASTEXITCODE -ne 0) {
  $output | Write-Host
  throw "Unable to list Supabase secrets."
}

$secretNames = [System.Collections.Generic.HashSet[string]]::new(
  [System.StringComparer]::Ordinal
)

foreach ($line in ($output | Out-String) -split "`r?`n") {
  if ($line -match "^\s*([A-Z][A-Z0-9_]+)\s*\|") {
    [void]$secretNames.Add($Matches[1])
  }
}

$missing = @()
foreach ($secret in $RequiredSecrets) {
  if (-not $secretNames.Contains($secret)) {
    $missing += $secret
  }
}

if ($missing.Count -gt 0) {
  Write-Host "Missing required Supabase secrets:"
  foreach ($secret in $missing) {
    Write-Host "  - $secret"
  }
  Write-Host ""
  Write-Host "Set them before releasing or deploying Edge Functions, for example:"
  Write-Host '  npx.cmd --yes supabase secrets set REVENUECAT_IOS_API_KEY="<secret>" --project-ref fcmwrmwdoqiqdnbisdpg'
  exit 1
}

Write-Host "Supabase secret preflight passed: $($RequiredSecrets -join ', ')"
