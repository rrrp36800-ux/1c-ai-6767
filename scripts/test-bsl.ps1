[CmdletBinding()]
param(
    [string]$SourceDir,
    [string]$ReportDirectory,
    [string]$LogPath,
    [string]$ResultPath,
    [string]$JarPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = '1.0.7'
$downloadUrl = 'https://github.com/1c-syntax/bsl-language-server/releases/download/v1.0.7/bsl-language-server-1.0.7-exec.jar'
$expectedSha256 = '9f62765edd344d66456da24c906eaf623a03c56e90e5aafee466200100909f64'

if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    $SourceDir = Join-Path $root 'tests/fixtures'
}
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    $ReportDirectory = Join-Path $root 'reports/bsl'
}
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $root 'reports/bsl-language-server.log'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    $ResultPath = Join-Path $ReportDirectory 'check-result.json'
}
if ([string]::IsNullOrWhiteSpace($JarPath)) {
    $JarPath = Join-Path $root 'tools/bsl-language-server/bsl-language-server-1.0.7-exec.jar'
}

$SourceDir = [System.IO.Path]::GetFullPath($SourceDir)
$ReportDirectory = [System.IO.Path]::GetFullPath($ReportDirectory)
$LogPath = [System.IO.Path]::GetFullPath($LogPath)
$ResultPath = [System.IO.Path]::GetFullPath($ResultPath)
$JarPath = [System.IO.Path]::GetFullPath($JarPath)
$reportPath = Join-Path $ReportDirectory 'bsl-json.json'

function Get-RepoRelativePath {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetFullPath($root)
    if ($fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return (($fullPath.Substring($rootPath.Length) -replace '^[\\/]+', '') -replace '\\', '/')
    }
    return $fullPath.Replace('\\', '/')
}

function Write-CheckResult {
    param(
        [ValidateSet('passed', 'failed', 'blocked', 'not_run')]
        [string]$Status,
        [string]$Details,
        [int]$ExitCode,
        [int]$AnalysisExitCode = -1,
        [int]$ErrorCount = 0,
        [int]$WarningCount = 0
    )

    $result = [ordered]@{
        schemaVersion = 1
        status = $Status
        check = 'bsl-static-analysis'
        tool = 'BSL Language Server'
        toolVersion = $version
        sourceDir = Get-RepoRelativePath $SourceDir
        report = Get-RepoRelativePath $reportPath
        log = Get-RepoRelativePath $LogPath
        analysisExitCode = $AnalysisExitCode
        diagnostics = [ordered]@{
            errors = $ErrorCount
            warnings = $WarningCount
        }
        details = $Details
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultPath) | Out-Null
    $result | ConvertTo-Json -Depth 8 | Set-Content -Path $ResultPath -Encoding UTF8

    $summaryPath = Join-Path $root 'reports/test-summary.json'
    $summary = $null
    if (Test-Path $summaryPath) {
        try {
            $summary = Get-Content -Raw -Path $summaryPath | ConvertFrom-Json
        } catch {
            $summary = $null
        }
    }
    if ($null -eq $summary) {
        $summary = [pscustomobject]@{
            schemaVersion = 1
            status = 'not_run'
            generatedAt = $null
            generatedBy = 'scripts/test-bsl.ps1'
            reason = $null
            checks = @()
            logFiles = @()
            nextAction = $null
        }
    }

    $otherChecks = @($summary.checks | Where-Object { $_.name -ne 'bsl-static-analysis' })
    $bslCheck = [ordered]@{
        name = 'bsl-static-analysis'
        status = $Status
        details = $Details
        report = Get-RepoRelativePath $reportPath
        log = Get-RepoRelativePath $LogPath
    }
    $summary.checks = @($otherChecks + [pscustomobject]$bslCheck)
    $summary.scope = 'bsl-static-analysis'
    $summary.generatedAt = [DateTime]::UtcNow.ToString('o')
    $summary.generatedBy = 'scripts/test-bsl.ps1'
    $summary.reason = if ($Status -eq 'blocked') { $Details } else { $null }
    $summary.logFiles = @($summary.checks | ForEach-Object { $_.log } | Where-Object { $_ }) | Select-Object -Unique
    $summary.nextAction = if ($Status -eq 'passed') {
        'BSL analysis passed. Configure the remaining 1C, unit, and UI/integration checks in the full pipeline.'
    } else {
        'Resolve the BSL analysis prerequisite or diagnostic failure, then rerun scripts/test-bsl.ps1.'
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8

    Write-Host ("BSL static analysis status: {0}. {1}" -f $Status, $Details)
    exit $ExitCode
}

New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $reportPath
Remove-Item -Force -ErrorAction SilentlyContinue $LogPath

if (-not (Test-Path $SourceDir -PathType Container)) {
    Write-CheckResult -Status 'failed' -Details ("BSL source directory not found: {0}" -f (Get-RepoRelativePath $SourceDir)) -ExitCode 1
}

$bslFiles = @(Get-ChildItem -Path $SourceDir -Filter '*.bsl' -File -Recurse)
if ($bslFiles.Count -eq 0) {
    Write-CheckResult -Status 'failed' -Details 'No .bsl files were found in the source directory.' -ExitCode 1
}

$java = Get-Command java -ErrorAction SilentlyContinue
if ($null -eq $java) {
    Write-CheckResult -Status 'blocked' -Details 'Java was not found on PATH. BSL Language Server requires a Java virtual machine.' -ExitCode 2
}

$javaVersionOutput = (& $java.Source -version 2>&1 | Out-String)
$javaMatch = [regex]::Match($javaVersionOutput, 'version "(?<major>[0-9]+)')
if (-not $javaMatch.Success) {
    Write-CheckResult -Status 'blocked' -Details 'Java was found, but its version could not be determined.' -ExitCode 2
}
$javaMajor = [int]$javaMatch.Groups['major'].Value
if ($javaMajor -lt 17) {
    Write-CheckResult -Status 'blocked' -Details ("Java {0} is unsupported. BSL Language Server requires Java 17 or newer." -f $javaMajor) -ExitCode 2
}

if (-not (Test-Path $JarPath -PathType Leaf)) {
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $JarPath) | Out-Null
        Invoke-WebRequest -Uri $downloadUrl -OutFile $JarPath
    } catch {
        Write-CheckResult -Status 'blocked' -Details ("Could not download BSL Language Server {0}: {1}" -f $version, $_.Exception.Message) -ExitCode 2
    }
}

try {
    $actualSha256 = (Get-FileHash -Path $JarPath -Algorithm SHA256).Hash.ToLowerInvariant()
} catch {
    Write-CheckResult -Status 'blocked' -Details ("Could not read the BSL Language Server archive: {0}" -f $_.Exception.Message) -ExitCode 2
}
if ($actualSha256 -ne $expectedSha256) {
    Write-CheckResult -Status 'failed' -Details ("SHA-256 mismatch for BSL Language Server {0}. Expected {1}, got {2}." -f $version, $expectedSha256, $actualSha256) -ExitCode 1
}

$stdoutPath = Join-Path $ReportDirectory 'bsl.stdout.log'
$stderrPath = Join-Path $ReportDirectory 'bsl.stderr.log'
Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath, $stderrPath

$commandDescription = "java -jar <bsl-language-server-{0}-exec.jar> --analyze --srcDir <source> --reporter json --outputDir <report-directory>" -f $version
$analysisExitCode = -1
try {
    Push-Location $root
    & $java.Source -jar $JarPath --analyze --srcDir $SourceDir --reporter json --outputDir $ReportDirectory 1> $stdoutPath 2> $stderrPath
    $analysisExitCode = $LASTEXITCODE
} catch {
    $analysisError = $_.Exception.Message
} finally {
    Pop-Location
}

$stdout = if (Test-Path $stdoutPath) { Get-Content -Raw -Path $stdoutPath } else { '' }
$stderr = if (Test-Path $stderrPath) { Get-Content -Raw -Path $stderrPath } else { '' }
$log = @(
    "Command: $commandDescription"
    "Java: $($javaVersionOutput.Trim())"
    "Process exit code: $analysisExitCode"
    ""
    '--- stdout ---'
    $stdout.TrimEnd()
    '--- stderr ---'
    $stderr.TrimEnd()
    if ($analysisError) { '--- PowerShell error ---'; $analysisError }
) -join [Environment]::NewLine
Set-Content -Path $LogPath -Value $log -Encoding UTF8
Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath, $stderrPath

if ($analysisError) {
    Write-CheckResult -Status 'failed' -Details ("BSL Language Server could not be started: {0}" -f $analysisError) -ExitCode 1 -AnalysisExitCode $analysisExitCode
}
if ($analysisExitCode -ne 0) {
    Write-CheckResult -Status 'failed' -Details ("BSL Language Server exited with code {0}. See the full log." -f $analysisExitCode) -ExitCode 1 -AnalysisExitCode $analysisExitCode
}
if (-not (Test-Path $reportPath -PathType Leaf)) {
    Write-CheckResult -Status 'failed' -Details 'BSL Language Server exited successfully but did not create the documented bsl-json.json report.' -ExitCode 1 -AnalysisExitCode $analysisExitCode
}

try {
    $analysis = Get-Content -Raw -Path $reportPath | ConvertFrom-Json
} catch {
    Write-CheckResult -Status 'failed' -Details ("The BSL JSON report could not be parsed: {0}" -f $_.Exception.Message) -ExitCode 1 -AnalysisExitCode $analysisExitCode
}

$diagnostics = @($analysis.fileinfos | ForEach-Object { @($_.diagnostics) })
$errorDiagnostics = @($diagnostics | Where-Object { $_.severity -eq 'Error' })
$warningDiagnostics = @($diagnostics | Where-Object { $_.severity -eq 'Warning' })
if ($errorDiagnostics.Count -gt 0) {
    Write-CheckResult -Status 'failed' -Details ("BSL analysis found {0} error diagnostic(s) and {1} warning(s). See the JSON report and full log." -f $errorDiagnostics.Count, $warningDiagnostics.Count) -ExitCode 1 -AnalysisExitCode $analysisExitCode -ErrorCount $errorDiagnostics.Count -WarningCount $warningDiagnostics.Count
}

Write-CheckResult -Status 'passed' -Details ("BSL analysis completed with 0 error diagnostic(s) and {0} warning(s)." -f $warningDiagnostics.Count) -ExitCode 0 -AnalysisExitCode $analysisExitCode -ErrorCount 0 -WarningCount $warningDiagnostics.Count
