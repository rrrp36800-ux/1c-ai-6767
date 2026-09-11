[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$SourceFile,
    [string]$OutputFile,
    [string]$V8Path,
    [switch]$SkipSkillBootstrap,
    [string]$ResultPath,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$toolRepository = 'https://github.com/Nikolay-Shirokov/cc-1c-skills.git'
$toolRef = '2c15b32e7f81f87cbdd5dba74964c4b25f5a0056'
$toolPlatform = 'codex'
$toolRuntime = 'powershell'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $root 'config/epf-build.json' }
if ([string]::IsNullOrWhiteSpace($ResultPath)) { $ResultPath = Join-Path $root 'reports/epf-build-result.json' }
if ([string]::IsNullOrWhiteSpace($LogPath)) { $LogPath = Join-Path $root 'reports/epf-build.log' }

function Resolve-ProjectPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $root $Path))
}

function Get-ProjectRelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetFullPath($root)
    if ($fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($rootPath.Length).TrimStart([char[]]@('\', '/')).Replace([char]92, [char]47)
    }
    return $fullPath.Replace([char]92, [char]47)
}

function ConvertTo-ProcessArgument([AllowNull()][string]$Argument) {
    if ($null -eq $Argument -or $Argument.Length -eq 0) { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append([char]34); $slashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq [char]92) { $slashes++; continue }
        if ($character -eq [char]34) {
            if ($slashes -gt 0) { [void]$builder.Append([char]92, (2 * $slashes + 1)) }
            [void]$builder.Append([char]34); $slashes = 0; continue
        }
        if ($slashes -gt 0) { [void]$builder.Append([char]92, $slashes) }
        [void]$builder.Append($character); $slashes = 0
    }
    if ($slashes -gt 0) { [void]$builder.Append([char]92, (2 * $slashes)) }
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

function Invoke-NativeProcess([string]$FilePath, [string[]]$Arguments) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath; $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true; $startInfo.RedirectStandardError = $true
    if ($null -ne $startInfo.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add([string]$argument) }
    } else {
        $startInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join ' ')
    }
    $process = New-Object System.Diagnostics.Process; $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Native process could not be started.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync(); $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{ Started = $true; ExitCode = $process.ExitCode; StdOut = [string]$stdoutTask.Result; StdErr = [string]$stderrTask.Result }
    } catch {
        return [pscustomobject]@{ Started = $false; ExitCode = 1; StdOut = ''; StdErr = $_.Exception.ToString() }
    } finally { $process.Dispose() }
}

function Write-BuildResult {
    param(
        [ValidateSet('passed', 'failed', 'blocked', 'not_run')][string]$Status,
        [string]$Details,
        [int]$ExitCode,
        [bool]$ArtifactExists = $false
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultPath) | Out-Null
    if (-not (Test-Path $LogPath -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
        Set-Content -Path $LogPath -Value $Details -Encoding UTF8
    }
    $result = [ordered]@{
        schemaVersion = 1
        status = $Status
        check = 'epf-build'
        tool = 'cc-1c-skills epf-build + 1C Designer'
        toolRevision = $toolRef
        sourceFile = Get-ProjectRelativePath $SourceFile
        outputFile = Get-ProjectRelativePath $OutputFile
        artifactExists = $ArtifactExists
        report = 'reports/epf-build-result.json'
        log = 'reports/epf-build.log'
        details = $Details
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -Path $ResultPath -Encoding UTF8

    $summaryPath = Join-Path $root 'reports/test-summary.json'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $summaryPath) | Out-Null
    $summary = $null
    if (Test-Path $summaryPath -PathType Leaf) {
        try { $summary = Get-Content -Raw -Path $summaryPath | ConvertFrom-Json } catch { $summary = $null }
    }
    if ($null -eq $summary) {
        $summary = [pscustomobject]@{
            schemaVersion = 1; scope = ''; status = ''; generatedAt = ''; generatedBy = ''; reason = $null
            checks = @(); logFiles = @(); nextAction = ''
        }
    }
    $summaryDetails = $Details
    if ($SourceFile) { $summaryDetails = $summaryDetails.Replace($SourceFile, (Get-ProjectRelativePath $SourceFile)) }
    if ($OutputFile) { $summaryDetails = $summaryDetails.Replace($OutputFile, (Get-ProjectRelativePath $OutputFile)) }
    $otherChecks = @($summary.checks | Where-Object { $_.name -ne 'epf-build' })
    $summary.checks = @($otherChecks + [pscustomobject][ordered]@{
        name = 'epf-build'
        status = $Status
        details = $summaryDetails
        report = 'reports/epf-build-result.json'
        log = 'reports/epf-build.log'
    })
    $summary.scope = 'epf-build-toolchain'
    $summary.status = $Status
    $summary.generatedAt = [DateTime]::UtcNow.ToString('o')
    $summary.generatedBy = 'scripts/build-epf.ps1'
    $summary.reason = if ($Status -eq 'blocked') { $Details } else { $null }
    $logFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($check in @($summary.checks)) {
        if ($check.log -and -not $logFiles.Contains([string]$check.log)) { $logFiles.Add([string]$check.log) }
    }
    $summary.logFiles = $logFiles
    $summary.nextAction = if ($Status -eq 'passed') { 'EPF build passed. Open the generated artifact on the target 1C platform.' } else { 'Initialize config/epf-build.json, then provide Windows, 1C:Enterprise 8.3, and the pinned cc-1c-skills toolchain before rerunning the build.' }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Host ("EPF build status: {0}. {1}" -f $Status, $Details)
    exit $ExitCode
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $ResultPath, $LogPath

if (-not (Test-Path $ConfigPath -PathType Leaf)) {
    Write-BuildResult -Status 'blocked' -Details ("EPF configuration not found: {0}. Run scripts/init-project.ps1 first." -f $ConfigPath) -ExitCode 2
}
try {
    $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
} catch {
    Write-BuildResult -Status 'failed' -Details ('Build configuration is not valid JSON: ' + $_.Exception.Message) -ExitCode 1
}
if ([string]::IsNullOrWhiteSpace($SourceFile)) { $SourceFile = [string]$config.sourceFile }
if ([string]::IsNullOrWhiteSpace($OutputFile)) { $OutputFile = [string]$config.outputFile }
if ([string]::IsNullOrWhiteSpace($V8Path)) { $V8Path = [string]$config.v8Path }
if ($config.cc1cSkills) {
    if (-not [string]::IsNullOrWhiteSpace([string]$config.cc1cSkills.repository)) { $toolRepository = [string]$config.cc1cSkills.repository }
    if (-not [string]::IsNullOrWhiteSpace([string]$config.cc1cSkills.ref)) { $toolRef = [string]$config.cc1cSkills.ref }
    if (-not [string]::IsNullOrWhiteSpace([string]$config.cc1cSkills.platform)) { $toolPlatform = [string]$config.cc1cSkills.platform }
    if (-not [string]::IsNullOrWhiteSpace([string]$config.cc1cSkills.runtime)) { $toolRuntime = [string]$config.cc1cSkills.runtime }
}
if ([string]::IsNullOrWhiteSpace($SourceFile) -or [string]::IsNullOrWhiteSpace($OutputFile)) {
    Write-BuildResult -Status 'failed' -Details 'Build configuration must define sourceFile and outputFile.' -ExitCode 1
}
if ($toolPlatform -ne 'codex' -or $toolRuntime -ne 'powershell') {
    Write-BuildResult -Status 'failed' -Details 'This build entry point requires cc1cSkills.platform=codex and cc1cSkills.runtime=powershell.' -ExitCode 1
}
$SourceFile = Resolve-ProjectPath $SourceFile
$OutputFile = Resolve-ProjectPath $OutputFile
if (-not (Test-Path $SourceFile -PathType Leaf)) {
    Write-BuildResult -Status 'failed' -Details ("EPF source XML not found: {0}" -f $SourceFile) -ExitCode 1
}
$sourceDir = Split-Path $SourceFile -Parent
$objectName = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile)
$modulePath = Join-Path $sourceDir (Join-Path $objectName 'Ext/ObjectModule.bsl')
if (-not (Test-Path $modulePath -PathType Leaf)) {
    Write-BuildResult -Status 'failed' -Details ("EPF object module not found: {0}" -f $modulePath) -ExitCode 1
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    Write-BuildResult -Status 'blocked' -Details 'EPF build requires Windows with the installed 1C:Enterprise 8.3 platform; GitHub-hosted Linux runners cannot produce the binary.' -ExitCode 2
}
$powershell = Get-Command powershell.exe -ErrorAction SilentlyContinue
if ($null -eq $powershell) {
    Write-BuildResult -Status 'blocked' -Details 'Windows PowerShell (powershell.exe) was not found; the pinned Codex PowerShell skill requires it.' -ExitCode 2
}
if ([string]::IsNullOrWhiteSpace($V8Path)) {
    $candidate = Get-ChildItem @("C:\Program Files\1cv8\*\bin\1cv8.exe", "C:\Program Files (x86)\1cv8\*\bin\1cv8.exe") -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Directory.Parent.Name } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1
    if ($candidate) { $V8Path = $candidate.FullName }
}
if (Test-Path $V8Path -PathType Container) { $V8Path = Join-Path $V8Path '1cv8.exe' }
if ([string]::IsNullOrWhiteSpace($V8Path) -or -not (Test-Path $V8Path -PathType Leaf)) {
    Write-BuildResult -Status 'blocked' -Details '1cv8.exe was not found. Install 1C:Enterprise 8.3 or provide -V8Path.' -ExitCode 2
}

$builder = Join-Path $root '.codex/skills/epf-build/scripts/epf-build.ps1'
if (-not (Test-Path $builder -PathType Leaf)) {
    if ($SkipSkillBootstrap) {
        Write-BuildResult -Status 'blocked' -Details 'The pinned cc-1c-skills Codex EPF builder is not installed. Run scripts/bootstrap-cc-1c-skills.ps1.' -ExitCode 2
    }
    $bootstrap = Join-Path $PSScriptRoot 'bootstrap-cc-1c-skills.ps1'
    $bootstrapResult = Invoke-NativeProcess $powershell.Source @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $bootstrap, '-ProjectDir', $root, '-Repository', $toolRepository, '-Ref', $toolRef, '-Platform', $toolPlatform, '-Runtime', $toolRuntime)
    $bootstrapOutput = @($bootstrapResult.StdOut.TrimEnd(), $bootstrapResult.StdErr.TrimEnd()) | Where-Object { $_ }
    if ($bootstrapOutput.Count -gt 0) { Set-Content -Path $LogPath -Value ($bootstrapOutput -join [Environment]::NewLine) -Encoding UTF8 }
    if ($bootstrapResult.ExitCode -eq 2) {
        Write-BuildResult -Status 'blocked' -Details 'The pinned cc-1c-skills toolchain could not be installed. See reports/epf-build.log.' -ExitCode 2
    }
    if (-not $bootstrapResult.Started -or $bootstrapResult.ExitCode -ne 0) {
        Write-BuildResult -Status 'failed' -Details ("The cc-1c-skills bootstrap failed with code {0}. See reports/epf-build.log." -f $bootstrapResult.ExitCode) -ExitCode 1
    }
}
if (-not (Test-Path $builder -PathType Leaf)) {
    Write-BuildResult -Status 'failed' -Details 'The cc-1c-skills EPF builder is still missing after bootstrap.' -ExitCode 1
}

$outDir = Split-Path $OutputFile -Parent
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $OutputFile
$command = @($powershell.Source, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $builder, '-V8Path', $V8Path, '-SourceFile', $SourceFile, '-OutputFile', $OutputFile)
$buildResult = Invoke-NativeProcess $powershell.Source @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $builder, '-V8Path', $V8Path, '-SourceFile', $SourceFile, '-OutputFile', $OutputFile)
$buildOutput = @($buildResult.StdOut.TrimEnd(), $buildResult.StdErr.TrimEnd()) | Where-Object { $_ }
$buildExitCode = $buildResult.ExitCode
$log = @(
    'Tool: cc-1c-skills epf-build'
    ('Tool revision: ' + $toolRef)
    ('Command: ' + ($command -join ' '))
    ('Exit code: ' + $buildExitCode)
    ''
    $buildOutput
)
Set-Content -Path $LogPath -Value ($log -join [Environment]::NewLine) -Encoding UTF8
if ($buildExitCode -ne 0) {
    Write-BuildResult -Status 'failed' -Details ("1C/cc-1c-skills build exited with code {0}. See reports/epf-build.log." -f $buildExitCode) -ExitCode 1
}
if (-not (Test-Path $OutputFile -PathType Leaf) -or (Get-Item $OutputFile).Length -eq 0) {
    Write-BuildResult -Status 'failed' -Details 'The build command returned success but did not create a non-empty .epf artifact.' -ExitCode 1
}
Write-BuildResult -Status 'passed' -Details ("Created non-empty EPF artifact: {0}" -f $OutputFile) -ExitCode 0 -ArtifactExists $true
