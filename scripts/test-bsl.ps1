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

if ([string]::IsNullOrWhiteSpace($SourceDir)) { $SourceDir = Join-Path $root 'src' }
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) { $ReportDirectory = Join-Path $root 'reports/bsl' }
if ([string]::IsNullOrWhiteSpace($LogPath)) { $LogPath = Join-Path $root 'reports/bsl-language-server.log' }
if ([string]::IsNullOrWhiteSpace($ResultPath)) { $ResultPath = Join-Path $ReportDirectory 'check-result.json' }
if ([string]::IsNullOrWhiteSpace($JarPath)) { $JarPath = Join-Path $root 'tools/bsl-language-server/bsl-language-server-1.0.7-exec.jar' }

$SourceDir = [System.IO.Path]::GetFullPath($SourceDir)
$ReportDirectory = [System.IO.Path]::GetFullPath($ReportDirectory)
$LogPath = [System.IO.Path]::GetFullPath($LogPath)
$ResultPath = [System.IO.Path]::GetFullPath($ResultPath)
$JarPath = [System.IO.Path]::GetFullPath($JarPath)
$reportPath = Join-Path $ReportDirectory 'bsl-json.json'

function ConvertTo-ProcessArgument {
    param([AllowNull()][string]$Argument)
    if ($null -eq $Argument -or $Argument.Length -eq 0) { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append([char]34)
    $slashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq [char]92) { $slashes++; continue }
        if ($character -eq [char]34) {
            if ($slashes -gt 0) { [void]$builder.Append([char]92, (2 * $slashes + 1)) }
            [void]$builder.Append([char]34)
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) { [void]$builder.Append([char]92, $slashes) }
        [void]$builder.Append($character)
        $slashes = 0
    }
    if ($slashes -gt 0) { [void]$builder.Append([char]92, (2 * $slashes)) }
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

function Invoke-NativeProcess {
    param([string]$FilePath, [string[]]$Arguments)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $argumentListProperty = $startInfo.PSObject.Properties['ArgumentList']
    if ($null -ne $argumentListProperty) {
        foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add([string]$argument) }
    } else {
        $startInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join ' ')
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Native process could not be started.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdoutTask.Result; StdErr = $stderrTask.Result }
    } catch {
        return [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = $_.Exception.ToString() }
    } finally {
        $process.Dispose()
    }
}

function Get-RepoRelativePath([string]$Path) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetFullPath($root)
    if ($fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return (($fullPath.Substring($rootPath.Length) -replace '^[\\/]+', '') -replace '\\', '/')
    }
    return $fullPath.Replace('\\', '/')
}

function Write-CheckResult {
    param(
        [ValidateSet('passed', 'failed', 'blocked', 'not_run')][string]$Status,
        [string]$Details,
        [int]$ExitCode,
        [int]$AnalysisExitCode = -1,
        [int]$ErrorCount = 0,
        [int]$WarningCount = 0
    )
    $relativeReport = Get-RepoRelativePath $reportPath
    $relativeLog = Get-RepoRelativePath $LogPath
    $result = [ordered]@{
        schemaVersion = 1; status = $Status; check = 'bsl-static-analysis'; tool = 'BSL Language Server'; toolVersion = $version
        sourceDir = Get-RepoRelativePath $SourceDir; report = $relativeReport; log = $relativeLog; analysisExitCode = $AnalysisExitCode
        diagnostics = [ordered]@{ errors = $ErrorCount; warnings = $WarningCount }; details = $Details
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultPath) | Out-Null
    $result | ConvertTo-Json -Depth 8 | Set-Content -Path $ResultPath -Encoding UTF8
    $summaryPath = Join-Path $root 'reports/test-summary.json'
    $summary = $null
    if (Test-Path $summaryPath -PathType Leaf) { try { $summary = Get-Content -Raw -Path $summaryPath | ConvertFrom-Json } catch { $summary = $null } }
    if ($null -eq $summary) {
        $summary = [pscustomobject]@{
            schemaVersion = 1; scope = ''; status = ''; generatedAt = ''; generatedBy = ''; reason = $null
            checks = @(); logFiles = @(); nextAction = ''
        }
    }
    $otherChecks = @($summary.checks | Where-Object { $_.name -ne 'bsl-static-analysis' })
    $summary.checks = @($otherChecks + [pscustomobject][ordered]@{ name = 'bsl-static-analysis'; status = $Status; details = $Details; report = $relativeReport; log = $relativeLog })
    $summary.scope = 'bsl-static-analysis'; $summary.status = $Status; $summary.generatedAt = [DateTime]::UtcNow.ToString('o'); $summary.generatedBy = 'scripts/test-bsl.ps1'
    $summary.reason = if ($Status -eq 'blocked') { $Details } else { $null }
    $summary.logFiles = @($summary.checks | ForEach-Object { $_.log } | Where-Object { $_ }) | Select-Object -Unique
    $summary.nextAction = if ($Status -eq 'passed') { 'BSL analysis passed. Configure the remaining 1C, unit, and UI/integration checks in the full pipeline.' } else { 'Resolve the BSL analysis prerequisite or diagnostic failure, then rerun scripts/test-bsl.ps1.' }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Host ("BSL static analysis status: {0}. {1}" -f $Status, $Details)
    exit $ExitCode
}

New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $reportPath, $LogPath
if (-not (Test-Path $SourceDir -PathType Container)) { Write-CheckResult -Status 'failed' -Details ('BSL source directory not found: ' + (Get-RepoRelativePath $SourceDir)) -ExitCode 1 }
$bslFiles = @(Get-ChildItem -Path $SourceDir -Filter '*.bsl' -File -Recurse)
if ($bslFiles.Count -eq 0) { Write-CheckResult -Status 'failed' -Details 'No .bsl files were found in the source directory.' -ExitCode 1 }

$javaCandidates = [System.Collections.Generic.List[string]]::new()
$pathJava = Get-Command java -ErrorAction SilentlyContinue
if ($pathJava) { $javaCandidates.Add([string]$pathJava.Source) }
if ($env:JAVA_HOME) { $javaCandidates.Add((Join-Path $env:JAVA_HOME 'bin/java.exe')) }
if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
    foreach ($pattern in @(
        'C:\Program Files\Eclipse Adoptium\jdk-*\bin\java.exe',
        'C:\Program Files\Java\jdk-*\bin\java.exe',
        'C:\Program Files\Microsoft\jdk-*\bin\java.exe'
    )) {
        foreach ($candidate in @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)) {
            $javaCandidates.Add($candidate.FullName)
        }
    }
}
$javaPath = $null; $javaVersionOutput = ''; $javaVersion = ''; $javaMajor = 0
foreach ($candidate in @($javaCandidates | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    $candidateResult = Invoke-NativeProcess -FilePath $candidate -Arguments @('-version')
    $candidateOutput = ([string]$candidateResult.StdOut + "`n" + [string]$candidateResult.StdErr).Trim()
    if ($candidateResult.ExitCode -ne 0) { continue }
    $candidateMatch = [regex]::Match($candidateOutput, '(?i)version\s+"(?<version>[^"]+)"')
    if (-not $candidateMatch.Success) { continue }
    $candidateVersion = $candidateMatch.Groups['version'].Value
    $candidateParts = $candidateVersion.Split('.')
    $candidateMajor = if ($candidateParts[0] -eq '1' -and $candidateParts.Count -gt 1) { [int]$candidateParts[1] } else { [int]($candidateParts[0] -replace '[^0-9].*$', '') }
    if ($candidateMajor -ge 17) {
        $javaPath = $candidate; $javaVersionOutput = $candidateOutput; $javaVersion = $candidateVersion; $javaMajor = $candidateMajor
        break
    }
}
if (-not $javaPath) { Write-CheckResult -Status 'blocked' -Details 'Java 17 or newer was not found. BSL Language Server requires a supported Java virtual machine.' -ExitCode 2 }

if (-not (Test-Path $JarPath -PathType Leaf)) {
    try { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $JarPath) | Out-Null; Invoke-WebRequest -Uri $downloadUrl -OutFile $JarPath }
    catch { Write-CheckResult -Status 'blocked' -Details ("Could not download BSL Language Server {0}: {1}" -f $version, $_.Exception.Message) -ExitCode 2 }
}
try { $actualSha256 = [string](Get-FileHash -Path $JarPath -Algorithm SHA256).Hash.ToLowerInvariant() }
catch { Write-CheckResult -Status 'blocked' -Details ('Could not read the BSL Language Server archive: ' + $_.Exception.Message) -ExitCode 2 }
if ($actualSha256 -ne $expectedSha256) { Write-CheckResult -Status 'failed' -Details ("SHA-256 mismatch for BSL Language Server {0}. Expected {1}, got {2}." -f $version, $expectedSha256, $actualSha256) -ExitCode 1 }

$stdoutPath = Join-Path $ReportDirectory 'bsl.stdout.log'; $stderrPath = Join-Path $ReportDirectory 'bsl.stderr.log'
Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath, $stderrPath
$analysisExitCode = -1; $analysisError = $null
try {
    Push-Location $root
    & $javaPath -jar $JarPath --analyze --srcDir $SourceDir --reporter json --outputDir $ReportDirectory 1> $stdoutPath 2> $stderrPath
    $analysisExitCode = $LASTEXITCODE
} catch { $analysisError = $_.Exception.Message } finally { Pop-Location }
$stdout = if (Test-Path $stdoutPath -PathType Leaf) { Get-Content -Raw -Path $stdoutPath } else { '' }
$stderr = if (Test-Path $stderrPath -PathType Leaf) { Get-Content -Raw -Path $stderrPath } else { '' }
if ($null -eq $stdout) { $stdout = '' }
if ($null -eq $stderr) { $stderr = '' }
$logParts = @(
    ('Command: java -jar <bsl-language-server-{0}-exec.jar> --analyze --srcDir <source> --reporter json --outputDir <report-directory>' -f $version)
    ('Java executable: ' + $javaPath); ('Java: ' + $javaVersionOutput); ('Process exit code: ' + $analysisExitCode); ''; '--- stdout ---'; $stdout.TrimEnd(); '--- stderr ---'; $stderr.TrimEnd()
)
if ($null -ne $analysisError) { $logParts += '--- PowerShell error ---'; $logParts += $analysisError }
Set-Content -Path $LogPath -Value ($logParts -join [Environment]::NewLine) -Encoding UTF8
Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath, $stderrPath
if ($null -ne $analysisError) { Write-CheckResult -Status 'failed' -Details ('BSL Language Server could not be started: ' + $analysisError) -ExitCode 1 -AnalysisExitCode $analysisExitCode }
if ($analysisExitCode -ne 0) { Write-CheckResult -Status 'failed' -Details ("BSL Language Server exited with code {0}. See the full log." -f $analysisExitCode) -ExitCode 1 -AnalysisExitCode $analysisExitCode }
if (-not (Test-Path $reportPath -PathType Leaf)) { Write-CheckResult -Status 'failed' -Details 'BSL Language Server exited successfully but did not create the documented bsl-json.json report.' -ExitCode 1 -AnalysisExitCode $analysisExitCode }
try { $analysis = Get-Content -Raw -Path $reportPath | ConvertFrom-Json }
catch { Write-CheckResult -Status 'failed' -Details ('The BSL JSON report could not be parsed: ' + $_.Exception.Message) -ExitCode 1 -AnalysisExitCode $analysisExitCode }
$diagnostics = @($analysis.fileinfos | ForEach-Object { @($_.diagnostics) })
$errorDiagnostics = @($diagnostics | Where-Object { $_.severity -eq 'Error' }); $warningDiagnostics = @($diagnostics | Where-Object { $_.severity -eq 'Warning' })
if ($errorDiagnostics.Count -gt 0) { Write-CheckResult -Status 'failed' -Details ("BSL analysis found {0} error diagnostic(s) and {1} warning(s). See the JSON report and full log." -f $errorDiagnostics.Count, $warningDiagnostics.Count) -ExitCode 1 -AnalysisExitCode $analysisExitCode -ErrorCount $errorDiagnostics.Count -WarningCount $warningDiagnostics.Count }
Write-CheckResult -Status 'passed' -Details ("BSL analysis completed with 0 error diagnostic(s) and {0} warning(s)." -f $warningDiagnostics.Count) -ExitCode 0 -AnalysisExitCode $analysisExitCode -ErrorCount 0 -WarningCount $warningDiagnostics.Count
