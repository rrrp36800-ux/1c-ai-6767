[CmdletBinding()]
param(
    [switch]$BslOnly,
    [switch]$EpfBuildOnly
)

$ErrorActionPreference = 'Stop'
if ($BslOnly -and $EpfBuildOnly) {
    Write-Host 'Use only one scope switch: -BslOnly or -EpfBuildOnly.' -ForegroundColor Red
    exit 1
}
$root = Split-Path -Parent $PSScriptRoot
$reportPath = Join-Path $root 'reports/test-summary.json'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reportPath) | Out-Null
$requiredPaths = @('AGENTS.md', 'README.md', 'config', 'docs', 'src', 'tests', 'scripts')
$missingPaths = @($requiredPaths | Where-Object { -not (Test-Path (Join-Path $root $_)) })
$layoutStatus = if ($missingPaths.Count -eq 0) { 'passed' } else { 'failed' }
$layoutDetails = if ($missingPaths.Count -eq 0) { 'Repository bootstrap layout is present.' } else { 'Missing paths: ' + ($missingPaths -join ', ') }

$runBsl = -not $EpfBuildOnly
$runEpf = -not $BslOnly
$powerShell = Get-Command pwsh -ErrorAction SilentlyContinue
if ($null -eq $powerShell) { $powerShell = Get-Command powershell -ErrorAction SilentlyContinue }

$bslStatus = 'not_run'
$bslDetails = 'BSL scope was not selected.'
$bslReport = 'reports/bsl/bsl-json.json'
$bslLog = 'reports/bsl-language-server.log'
if ($runBsl) {
    $bslStatus = 'blocked'
    $bslDetails = 'BSL helper did not produce a result.'
    if ($null -ne $powerShell) {
        & $powerShell.Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-bsl.ps1')
        $bslExitCode = $LASTEXITCODE
        $bslResultPath = Join-Path $root 'reports/bsl/check-result.json'
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
}

$epfStatus = 'not_run'
$epfDetails = 'EPF build scope was not selected.'
$epfReport = 'reports/epf-build-result.json'
$epfLog = 'reports/epf-build.log'
if ($runEpf) {
    $epfStatus = 'blocked'
    $epfDetails = 'EPF build helper did not produce a result.'
    if ($null -ne $powerShell) {
        & $powerShell.Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build-epf.ps1')
        $epfExitCode = $LASTEXITCODE
        $epfResultPath = Join-Path $root 'reports/epf-build-result.json'
        if (Test-Path $epfResultPath -PathType Leaf) {
            try {
                $epfResult = Get-Content -Raw -Path $epfResultPath | ConvertFrom-Json
                $epfStatus = [string]$epfResult.status
                $epfDetails = [string]$epfResult.details
                $epfReport = [string]$epfResult.report
                $epfLog = [string]$epfResult.log
            } catch {
                $epfStatus = 'failed'
                $epfDetails = 'EPF build helper result could not be parsed: ' + $_.Exception.Message
            }
        } elseif ($epfExitCode -eq 0) {
            $epfStatus = 'failed'
            $epfDetails = 'EPF build helper returned success without writing its result.'
        }
    } else {
        $epfDetails = 'Neither pwsh nor Windows PowerShell was found to run scripts/build-epf.ps1.'
    }
}

$checks = @([ordered]@{
    name = 'repository-layout'
    status = $layoutStatus
    details = $layoutDetails
})
if ($runBsl) {
    $checks += [ordered]@{ name = 'bsl-static-analysis'; status = $bslStatus; details = $bslDetails; report = $bslReport; log = $bslLog }
}
if ($runEpf) {
    $epfDetailsForSummary = $epfDetails
    if ($epfResultPath -and (Test-Path $epfResultPath -PathType Leaf)) {
        $epfDetailsForSummary = $epfDetailsForSummary.Replace((Join-Path $root 'build/ToolchainSmoke.epf'), 'build/ToolchainSmoke.epf')
    }
    $checks += [ordered]@{ name = 'epf-build'; status = $epfStatus; details = $epfDetailsForSummary; report = $epfReport; log = $epfLog }
}
if (-not $BslOnly -and -not $EpfBuildOnly) {
    $checks += [ordered]@{ name = '1c-build'; status = 'not_run'; details = 'Full configuration build has not been confirmed.' }
    $checks += [ordered]@{ name = 'unit-tests'; status = 'not_run'; details = 'YaXUnit installation and invocation have not been confirmed.' }
    $checks += [ordered]@{ name = 'ui-integration-tests'; status = 'not_run'; details = 'No 1C test base or UI/integration runner is configured.' }
}

$statuses = @($checks | ForEach-Object { $_.status })
$status = if ($statuses -contains 'failed') { 'failed' } elseif (($statuses -contains 'blocked') -or ($statuses -contains 'not_run')) { 'blocked' } else { 'passed' }
$scope = if ($BslOnly) { 'bsl-static-analysis' } elseif ($EpfBuildOnly) { 'epf-build-toolchain' } else { 'full-pipeline' }
$logFiles = [System.Collections.Generic.List[string]]::new()
foreach ($check in @($checks)) {
    if ($check.log -and -not $logFiles.Contains([string]$check.log)) { $logFiles.Add([string]$check.log) }
}
$summary = [ordered]@{
    schemaVersion = 1
    scope = $scope
    status = $status
    generatedAt = [DateTime]::UtcNow.ToString('o')
    generatedBy = 'scripts/test.ps1'
    reason = if ($status -eq 'blocked') { 'One or more checks are not configured or cannot run in the current environment.' } else { $null }
    checks = $checks
    logFiles = $logFiles
    nextAction = if ($status -eq 'passed') { 'All configured checks passed.' } elseif ($EpfBuildOnly) { 'Provide Windows 1C:Enterprise 8.3 and rerun the EPF build scope.' } else { 'Resolve failed or blocked checks, then rerun the selected scope.' }
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8
Write-Host ("Test summary status: {0}. Scope: {1}." -f $status, $scope)
switch ($status) {
    'passed' { exit 0 }
    'failed' { exit 1 }
    default { exit 2 }
}
