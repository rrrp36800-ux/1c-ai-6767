[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Task
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$rootResolvedPath = (Resolve-Path -LiteralPath $root).Path
$reportDir = Join-Path $root 'reports/agent-task'
$summaryPath = Join-Path $reportDir 'summary.json'
$promptPath = Join-Path $reportDir 'prompt.md'
$codexLogPath = Join-Path $reportDir 'codex.jsonl'
$codexFinalPath = Join-Path $reportDir 'codex-final.md'
$model = 'gpt-5.6-luna'

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function Get-ProjectRelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $pathForResolution = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $rootResolvedPath $Path }
    $fullPath = [System.IO.Path]::GetFullPath($pathForResolution)
    $rootPath = $rootResolvedPath.TrimEnd([char[]]@(92, 47))
    $rootPrefixBackslash = $rootPath + [char]92
    $rootPrefixSlash = $rootPath + [char]47
    if ($fullPath.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }
    if ($fullPath.StartsWith($rootPrefixBackslash, [System.StringComparison]::OrdinalIgnoreCase) -or $fullPath.StartsWith($rootPrefixSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($rootPath.Length).TrimStart([char[]]@(92, 47)).Replace([char]92, [char]47)
    }
    return $fullPath.Replace([char]92, [char]47)
}

function Write-RunnerSummary {
    param(
        [ValidateSet('passed', 'failed', 'blocked', 'not_run')]
        [string]$Status,
        [string]$Details,
        [string]$Branch,
        [string]$BranchAfter,
        [string]$HeadBefore,
        [string]$HeadAfter,
        [string]$TaskRelative,
        [string]$AgentStatus,
        [int]$AgentExitCode,
        [string]$TestStatus,
        [int]$TestExitCode,
        [object[]]$TestRuns
    )
    $changedFiles = @()
    if ($git) {
        $changedFiles += @(& $git.Source -C $root diff --name-only 2>&1)
        $changedFiles += @(& $git.Source -C $root ls-files --others --exclude-standard 2>&1)
        $changedFiles = @($changedFiles | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { Get-ProjectRelativePath $_ }) | Sort-Object -Unique
    }
    $summary = [ordered]@{
        schemaVersion = 2
        status = $Status
        details = $Details
        branch = $Branch
        git = [ordered]@{
            branchAfter = $BranchAfter
            headBefore = $HeadBefore
            headAfter = $HeadAfter
        }
        task = $TaskRelative
        model = $model
        agent = [ordered]@{
            status = $AgentStatus
            exitCode = $AgentExitCode
            log = 'reports/agent-task/codex.jsonl'
            finalMessage = 'reports/agent-task/codex-final.md'
        }
        tests = [ordered]@{
            status = $TestStatus
            exitCode = $TestExitCode
            scopes = @($TestRuns)
        }
        changedFiles = @($changedFiles)
        logs = @(
            'reports/agent-task/codex.jsonl'
            'reports/agent-task/codex-final.md'
            'reports/agent-task/test-bsl.log'
            'reports/agent-task/test-bsl-summary.json'
            'reports/agent-task/test-epf.log'
            'reports/agent-task/test-epf-summary.json'
        )
    }
    $summary | ConvertTo-Json -Depth 12 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Host ("Agent task status: {0}. {1}" -f $Status, $Details)
    if ($Status -eq 'passed') { exit 0 }
    if ($Status -eq 'failed') { exit 1 }
    exit 2
}

$taskInputPath = if ([System.IO.Path]::IsPathRooted($Task)) { $Task } else { Join-Path (Get-Location).Path $Task }
$taskFullPath = [System.IO.Path]::GetFullPath($taskInputPath)
$taskRelative = Get-ProjectRelativePath $taskFullPath
if (-not (Test-Path -LiteralPath $taskFullPath -PathType Leaf)) {
    Write-RunnerSummary -Status 'blocked' -Details ("Task file not found: {0}" -f $taskRelative) -Branch '' -BranchAfter '' -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 2 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
$taskResolvedPath = (Resolve-Path -LiteralPath $taskFullPath).Path
$rootComparisonPath = $rootResolvedPath.TrimEnd([char[]]@(92, 47))
$taskInsideRepository = $taskResolvedPath.Equals($rootComparisonPath, [System.StringComparison]::OrdinalIgnoreCase) -or
    $taskResolvedPath.StartsWith($rootComparisonPath + [char]92, [System.StringComparison]::OrdinalIgnoreCase) -or
    $taskResolvedPath.StartsWith($rootComparisonPath + [char]47, [System.StringComparison]::OrdinalIgnoreCase)
if (-not $taskInsideRepository) {
    Write-RunnerSummary -Status 'blocked' -Details 'The task file must resolve to a path inside the current repository.' -Branch '' -BranchAfter '' -HeadBefore '' -HeadAfter '' -TaskRelative $taskResolvedPath -AgentStatus 'not_run' -AgentExitCode 2 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
$taskFullPath = $taskResolvedPath
$taskRelative = Get-ProjectRelativePath $taskFullPath

$requiredHeadings = @(
    '# Goal'
    '# Context'
    '# Requirements'
    '# Acceptance criteria'
    '# Allowed changes'
    '# Forbidden changes'
    '# Required tests'
)
$taskContent = Get-Content -Raw -LiteralPath $taskFullPath
$taskHeadings = @($taskContent -split "`r?`n" | Where-Object { $_ -match '^# ' } | ForEach-Object { $_.TrimEnd() })
if (($taskHeadings -join "`n") -ne ($requiredHeadings -join "`n")) {
    Write-RunnerSummary -Status 'failed' -Details 'Task file must contain exactly the seven required level-one headings in the documented order.' -Branch '' -BranchAfter '' -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 1 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}

$agentsPath = Join-Path $root 'AGENTS.md'
if (-not (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
    Write-RunnerSummary -Status 'failed' -Details 'AGENTS.md is required and was not found.' -Branch '' -BranchAfter '' -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 1 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
$agentsContent = Get-Content -Raw -LiteralPath $agentsPath
if ([string]::IsNullOrWhiteSpace($agentsContent)) {
    Write-RunnerSummary -Status 'failed' -Details 'AGENTS.md is empty.' -Branch '' -BranchAfter '' -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 1 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $git) {
    Write-RunnerSummary -Status 'blocked' -Details 'Git is required by the local task runner.' -Branch '' -BranchAfter '' -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 2 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
$repoRoot = (& $git.Source -C $root rev-parse --show-toplevel 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    Write-RunnerSummary -Status 'failed' -Details 'The current directory is not inside a Git repository.' -Branch '' -BranchAfter '' -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 1 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
$repoRoot = [System.IO.Path]::GetFullPath($repoRoot)
if ($repoRoot -ne $root) {
    Write-RunnerSummary -Status 'failed' -Details 'The runner must execute from the repository root.' -Branch '' -BranchAfter '' -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 1 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
$branch = (& $git.Source -C $root branch --show-current 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    Write-RunnerSummary -Status 'failed' -Details 'Could not determine the current Git branch.' -Branch '' -BranchAfter '' -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 1 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
if ($branch -eq 'main') {
    Write-RunnerSummary -Status 'blocked' -Details 'The task runner is disabled on main.' -Branch $branch -BranchAfter $branch -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 2 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
$workingTree = @(& $git.Source -C $root status --porcelain=v1 --untracked-files=all 2>&1)
if ($LASTEXITCODE -ne 0) {
    Write-RunnerSummary -Status 'failed' -Details 'Could not inspect the Git working tree.' -Branch $branch -BranchAfter $branch -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 1 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
if ($workingTree.Count -gt 0) {
    Write-RunnerSummary -Status 'blocked' -Details 'The working tree is not clean. Commit or stash existing changes before running a task.' -Branch $branch -BranchAfter $branch -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 2 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
$headBefore = (& $git.Source -C $root rev-parse --verify HEAD 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headBefore)) {
    Write-RunnerSummary -Status 'failed' -Details 'Could not record the current Git HEAD before starting Codex.' -Branch $branch -BranchAfter $branch -HeadBefore '' -HeadAfter '' -TaskRelative $taskRelative -AgentStatus 'not_run' -AgentExitCode 1 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}

$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($null -eq $codex) {
    Write-RunnerSummary -Status 'blocked' -Details 'Codex CLI is not installed or is not available on PATH.' -Branch $branch -BranchAfter $branch -HeadBefore $headBefore -HeadAfter $headBefore -TaskRelative $taskRelative -AgentStatus 'blocked' -AgentExitCode 2 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
$codexHelp = (& $codex.Source --help 2>&1 | Out-String)
$codexHelpExitCode = $LASTEXITCODE
$execHelp = (& $codex.Source exec --help 2>&1 | Out-String)
$execHelpExitCode = $LASTEXITCODE
$helpText = $codexHelp + "`n" + $execHelp
if ($codexHelpExitCode -ne 0 -or $execHelpExitCode -ne 0 -or $helpText -notmatch '--model' -or $helpText -notmatch '--sandbox' -or $helpText -notmatch '--json' -or $helpText -notmatch '--output-last-message') {
    Write-RunnerSummary -Status 'blocked' -Details 'Installed Codex CLI does not expose the documented non-interactive model, sandbox, JSON, and final-message output flags.' -Branch $branch -BranchAfter $branch -HeadBefore $headBefore -HeadAfter $headBefore -TaskRelative $taskRelative -AgentStatus 'blocked' -AgentExitCode 2 -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}

$prompt = @"
You are the implementation agent for the current local repository.

MANDATORY INSTRUCTIONS:
1. Read and obey the AGENTS.md content included below.
2. Read and obey the selected architect task included below.
3. Work only in the current repository and current branch: $branch.
4. Implement only the selected task. Do not add 1C business logic or unrelated features.
5. Do not run git push, git merge, create a pull request, or switch to main.
6. Do not modify generated build or report artifacts as deliverables.
7. Run the required tests from the task and leave the working tree with the intended source changes only. Do not commit; the runner owns no commit or push operation.

The runner will execute the configured BSL and EPF scopes after this turn. Do not claim success unless both scopes pass.

===== AGENTS.md (mandatory) =====
$agentsContent
===== END AGENTS.md =====

===== SELECTED TASK: $taskRelative (mandatory) =====
$taskContent
===== END SELECTED TASK =====
"@
Set-Content -Path $promptPath -Value $prompt -Encoding UTF8

$oldGitConfigCount = $env:GIT_CONFIG_COUNT
$oldGitConfigKey0 = $env:GIT_CONFIG_KEY_0
$oldGitConfigValue0 = $env:GIT_CONFIG_VALUE_0
$oldGitTerminalPrompt = $env:GIT_TERMINAL_PROMPT
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'remote.origin.pushurl'
$env:GIT_CONFIG_VALUE_0 = 'DISABLED_BY_AGENT_TASK_RUNNER'
$env:GIT_TERMINAL_PROMPT = '0'
try {
    Push-Location $root
    $codexOutput = @(Get-Content -Raw -Path $promptPath | & $codex.Source exec --model $model --sandbox workspace-write --json --output-last-message $codexFinalPath - 2>&1)
    $codexExitCode = $LASTEXITCODE
    $codexOutput | Set-Content -Path $codexLogPath -Encoding UTF8
} catch {
    $codexExitCode = 1
    Set-Content -Path $codexLogPath -Value $_.Exception.ToString() -Encoding UTF8
} finally {
    Pop-Location
    if ($null -eq $oldGitConfigCount) { Remove-Item Env:GIT_CONFIG_COUNT -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_COUNT = $oldGitConfigCount }
    if ($null -eq $oldGitConfigKey0) { Remove-Item Env:GIT_CONFIG_KEY_0 -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_KEY_0 = $oldGitConfigKey0 }
    if ($null -eq $oldGitConfigValue0) { Remove-Item Env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_VALUE_0 = $oldGitConfigValue0 }
    if ($null -eq $oldGitTerminalPrompt) { Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue } else { $env:GIT_TERMINAL_PROMPT = $oldGitTerminalPrompt }
}
$codexText = if (Test-Path -LiteralPath $codexLogPath -PathType Leaf) { Get-Content -Raw -LiteralPath $codexLogPath } else { '' }
$agentStatus = if ($codexExitCode -eq 0) { 'passed' } elseif ($codexText -match '(?i)(unknown model|model.*not.*(found|available|support)|unsupported.*model|invalid.*model)') { 'blocked' } else { 'failed' }

$headAfter = (& $git.Source -C $root rev-parse --verify HEAD 2>&1 | Out-String).Trim()
$branchAfter = (& $git.Source -C $root branch --show-current 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headAfter) -or [string]::IsNullOrWhiteSpace($branchAfter)) {
    Write-RunnerSummary -Status 'failed' -Details 'Could not verify Git HEAD or branch after Codex.' -Branch $branch -BranchAfter $branchAfter -HeadBefore $headBefore -HeadAfter $headAfter -TaskRelative $taskRelative -AgentStatus $agentStatus -AgentExitCode $codexExitCode -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
if ($headAfter -ne $headBefore) {
    Write-RunnerSummary -Status 'failed' -Details 'Codex changed Git HEAD. The runner did not rewrite or roll back history and stopped before testing.' -Branch $branch -BranchAfter $branchAfter -HeadBefore $headBefore -HeadAfter $headAfter -TaskRelative $taskRelative -AgentStatus $agentStatus -AgentExitCode $codexExitCode -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}
if ($branchAfter -ne $branch) {
    Write-RunnerSummary -Status 'failed' -Details 'Codex changed the current Git branch. The runner stopped before testing.' -Branch $branch -BranchAfter $branchAfter -HeadBefore $headBefore -HeadAfter $headAfter -TaskRelative $taskRelative -AgentStatus $agentStatus -AgentExitCode $codexExitCode -TestStatus 'not_run' -TestExitCode 2 -TestRuns @()
}

$testScript = Join-Path $root 'scripts/test.ps1'
$testPowerShell = Get-Command pwsh -ErrorAction SilentlyContinue
if ($null -eq $testPowerShell) { $testPowerShell = Get-Command powershell -ErrorAction SilentlyContinue }
if ($null -eq $testPowerShell -or -not (Test-Path -LiteralPath $testScript -PathType Leaf)) {
    Write-RunnerSummary -Status 'blocked' -Details 'The existing scripts/test.ps1 or a PowerShell executable is unavailable.' -Branch $branch -BranchAfter $branchAfter -HeadBefore $headBefore -HeadAfter $headAfter -TaskRelative $taskRelative -AgentStatus $agentStatus -AgentExitCode $codexExitCode -TestStatus 'blocked' -TestExitCode 2 -TestRuns @()
}

$trackedTestSummary = Join-Path $root 'reports/test-summary.json'
$testSummaryBackup = Join-Path $reportDir 'test-summary.before.json'
$hadTrackedTestSummary = Test-Path -LiteralPath $trackedTestSummary -PathType Leaf
if ($hadTrackedTestSummary) { Copy-Item -LiteralPath $trackedTestSummary -Destination $testSummaryBackup -Force }

function Invoke-TestScope {
    param(
        [string]$Scope,
        [string]$LogPath,
        [string]$SummaryArtifactPath
    )
    $output = @()
    $exitCode = 1
    try {
        Remove-Item -LiteralPath $trackedTestSummary -Force -ErrorAction SilentlyContinue
        $output = @(& $testPowerShell.Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $testScript $Scope 2>&1)
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { [string]$_ } | Set-Content -Path $LogPath -Encoding UTF8
        if (Test-Path -LiteralPath $trackedTestSummary -PathType Leaf) {
            Copy-Item -LiteralPath $trackedTestSummary -Destination $SummaryArtifactPath -Force
            try {
                $scopeSummary = Get-Content -Raw -LiteralPath $trackedTestSummary | ConvertFrom-Json
                $status = [string]$scopeSummary.status
            } catch {
                $status = 'failed'
            }
        } else {
            $status = if ($exitCode -eq 2) { 'blocked' } else { 'failed' }
        }
        if ($status -notin @('passed', 'failed', 'blocked')) {
            $status = if ($exitCode -eq 2) { 'blocked' } else { 'failed' }
        }
    } catch {
        $status = 'failed'
        $exitCode = 1
        Set-Content -Path $LogPath -Value $_.Exception.ToString() -Encoding UTF8
    }
    [pscustomobject]@{
        scope = $Scope
        status = $status
        exitCode = $exitCode
        log = (Get-ProjectRelativePath $LogPath)
        summary = (Get-ProjectRelativePath $SummaryArtifactPath)
    }
}

$bslLogPath = Join-Path $reportDir 'test-bsl.log'
$bslSummaryArtifact = Join-Path $reportDir 'test-bsl-summary.json'
$epfLogPath = Join-Path $reportDir 'test-epf.log'
$epfSummaryArtifact = Join-Path $reportDir 'test-epf-summary.json'
$bslResult = $null
$epfResult = $null
try {
    $bslResult = Invoke-TestScope -Scope '-BslOnly' -LogPath $bslLogPath -SummaryArtifactPath $bslSummaryArtifact
    $epfResult = Invoke-TestScope -Scope '-EpfBuildOnly' -LogPath $epfLogPath -SummaryArtifactPath $epfSummaryArtifact
} finally {
    if ($hadTrackedTestSummary) {
        Copy-Item -LiteralPath $testSummaryBackup -Destination $trackedTestSummary -Force
    } elseif (Test-Path -LiteralPath $trackedTestSummary -PathType Leaf) {
        Remove-Item -LiteralPath $trackedTestSummary -Force
    }
}
$testRuns = @($bslResult, $epfResult)
$testStatuses = @($testRuns | ForEach-Object { $_.status })
$testStatus = if ($testStatuses -contains 'failed') { 'failed' } elseif (($testStatuses -contains 'blocked') -or ($testStatuses -contains 'not_run')) { 'blocked' } else { 'passed' }
$testExitCode = if ($testStatus -eq 'passed') { 0 } elseif ($testStatus -eq 'failed') { 1 } else { 2 }
if ($agentStatus -eq 'blocked' -or $testStatus -eq 'blocked') {
    $overallStatus = 'blocked'
} elseif ($agentStatus -eq 'failed' -or $testStatus -eq 'failed') {
    $overallStatus = 'failed'
} elseif ($agentStatus -eq 'passed' -and $testStatus -eq 'passed') {
    $overallStatus = 'passed'
} else {
    $overallStatus = 'failed'
}
$overallDetails = if ($overallStatus -eq 'passed') { 'Codex completed; BSL and EPF configured scopes passed.' } elseif ($overallStatus -eq 'blocked') { 'The agent task could not be completed in the current environment; inspect the scoped summaries and logs.' } else { 'The agent or a configured test scope failed; inspect the scoped summaries and logs.' }
Write-RunnerSummary -Status $overallStatus -Details $overallDetails -Branch $branch -BranchAfter $branchAfter -HeadBefore $headBefore -HeadAfter $headAfter -TaskRelative $taskRelative -AgentStatus $agentStatus -AgentExitCode $codexExitCode -TestStatus $testStatus -TestExitCode $testExitCode -TestRuns $testRuns
