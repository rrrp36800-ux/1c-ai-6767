[CmdletBinding()]
param(
    [switch]$BslOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$reportPath = Join-Path $root 'reports/test-summary.json'
$requiredPaths = @('AGENTS.md', 'README.md', 'docs', 'src', 'tests', 'scripts', 'reports')
$missingPaths = @($requiredPaths | Where-Object { -not (Test-Path (Join-Path $root $_)) })

$layoutStatus = if ($missingPaths.Count -eq 0) { 'passed' } else { 'failed' }
$layoutDetails = if ($missingPaths.Count -eq 0) { 'Repository bootstrap layout is present.' } else { 'Missing paths: ' + ($missingPaths -join ', ') }

$bslResultPath = Join-Path $root 'reports/bsl/check-result.json'
$bslScript = Join-Path $PSScriptRoot 'test-bsl.ps1'
$bslStatus = 'blocked'
$bslDetails = 'BSL helper did not produce a result.'
$bslReport = 'reports/bsl/bsl-json.json'
$bslLog = 'reports/bsl-language-server.log'

$powerShell = Get-Command pwsh -ErrorAction SilentlyContinue
if ($null -eq $powerShell) {
    $powerShell = Get-Command powershell -ErrorAction SilentlyContinue
}
if ($null -ne $powerShell) {
    & $powerShell.Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bslScript
    $bslExitCode = $LASTEXITCODE
    if (Test-Path $bslResultPath -PathType Leaf) {
        try {
            $bslResult = Get-Content -Raw -Path $bslResultPath | ConvertFrom-Json
            $bslStatus = [string]$bslResult.status
            $bslDetails = [string]$bslResult.details
            $bslReport = [string]$bslResult.report
            $bslLog = [string]$bslResult.log
        } catch {
            $bslStatus = 'failed'
            $bslDetails = 'BSL helper result could not be parsed: ' + $_.Exception.Message
        }
    } elseif ($bslExitCode -eq 0) {
        $bslStatus = 'failed'
        $bslDetails = 'BSL helper returned success without writing its result.'
    }
} else {
    $bslDetails = 'Neither pwsh nor Windows PowerShell was found to run scripts/test-bsl.ps1.'
}

$bslCheck = [ordered]@{
    name = 'bsl-static-analysis'
    status = $bslStatus
    details = $bslDetails
    report = $bslReport
    log = $bslLog
}
$checks = @(
    $bslCheck
    [ordered]@{
        name = 'repository-layout'
        status = $layoutStatus
        details = $layoutDetails
    }
)

if (-not $BslOnly) {
    $checks += [ordered]@{
        name = '1c-build'
        status = 'not_run'
        details = 'A local 1C:Enterprise 8.3 build command has not been confirmed.'
    }
    $checks += [ordered]@{
        name = 'unit-tests'
        status = 'not_run'
        details = 'YaXUnit installation and invocation have not been confirmed.'
    }
    $checks += [ordered]@{
        name = 'ui-integration-tests'
        status = 'not_run'
        details = 'No 1C test base or UI/integration runner is configured.'
    }
}

$checkStatuses = @($checks | ForEach-Object { $_.status })
$status = if ($checkStatuses -contains 'failed') {
    'failed'
} elseif (($checkStatuses -contains 'blocked') -or ($checkStatuses -contains 'not_run')) {
    'blocked'
} elseif (($checkStatuses | Where-Object { $_ -ne 'passed' }).Count -eq 0) {
    'passed'
} else {
    'blocked'
}

$logFiles = @($checks | ForEach-Object { $_.log } | Where-Object { $_ }) | Select-Object -Unique
$summary = [ordered]@{
    schemaVersion = 1
    scope = if ($BslOnly) { 'bsl-static-analysis' } else { 'full-pipeline' }
    status = $status
    generatedAt = [DateTime]::UtcNow.ToString('o')
    generatedBy = 'scripts/test.ps1'
    reason = if ($status -eq 'blocked') { 'One or more checks are not configured or cannot run in the current environment.' } else { $null }
    checks = $checks
    logFiles = $logFiles
    nextAction = if ($BslOnly -and $status -eq 'passed') {
        'BSL analysis passed. Configure the remaining 1C, unit, and UI/integration checks in the full pipeline.'
    } elseif ($status -eq 'passed') {
        'All configured checks passed.'
    } else {
        'Resolve failed or blocked checks, then rerun the pipeline.'
    }
}

$summary | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8
Write-Host ("Test summary status: {0}. Scope: {1}." -f $status, $summary.scope)

switch ($status) {
    'passed' { exit 0 }
    'failed' { exit 1 }
    default { exit 2 }
}
