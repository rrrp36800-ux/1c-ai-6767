[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$reportPath = Join-Path $root 'reports/test-summary.json'

$requiredPaths = @('AGENTS.md', 'README.md', 'docs', 'src', 'tests', 'scripts', 'reports')
$missingPaths = @($requiredPaths | Where-Object { -not (Test-Path (Join-Path $root $_)) })

$layoutStatus = if ($missingPaths.Count -eq 0) { 'ready' } else { 'failed' }
$layoutDetails = if ($missingPaths.Count -eq 0) { 'Repository bootstrap layout is present.' } else { 'Missing paths: ' + ($missingPaths -join ', ') }

$checks = @(
  [ordered]@{
    name = 'repository-layout'
    status = $layoutStatus
    details = $layoutDetails
  }
  [ordered]@{
    name = 'bsl-static-analysis'
    status = 'not_run'
    details = 'BSL Language Server command and version are not configured in this scaffold.'
  }
  [ordered]@{
    name = '1c-build'
    status = 'not_run'
    details = 'A local 1C:Enterprise 8.3 build command has not been confirmed.'
  }
  [ordered]@{
    name = 'unit-tests'
    status = 'not_run'
    details = 'YaXUnit installation and invocation have not been confirmed.'
  }
  [ordered]@{
    name = 'ui-integration-tests'
    status = 'not_run'
    details = 'No 1C test base or UI/integration runner is configured.'
  }
)

$status = if ($checks.status -contains 'failed') { 'failed' } elseif ($checks.status -contains 'not_run') { 'blocked' } else { 'ready' }
$summary = [ordered]@{
  schemaVersion = 1
  status = $status
  generatedAt = [DateTime]::UtcNow.ToString('o')
  checks = $checks
  logFiles = @()
  nextAction = 'Confirm the local 1C, BSL Language Server, YaXUnit and UI test toolchain before enabling real checks.'
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding UTF8
Write-Host ("Wrote {0} with status '{1}'. No test was reported as passed." -f $reportPath, $status)

if ($status -eq 'failed') { exit 1 }
exit 2
