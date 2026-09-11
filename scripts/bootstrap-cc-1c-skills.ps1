[CmdletBinding()]
param(
    [string]$ProjectDir,
    [string]$ToolRoot,
    [string]$Repository = 'https://github.com/Nikolay-Shirokov/cc-1c-skills.git',
    [string]$Ref = '2c15b32e7f81f87cbdd5dba74964c4b25f5a0056'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectDir)) { $ProjectDir = $root }
if ([string]::IsNullOrWhiteSpace($ToolRoot)) { $ToolRoot = Join-Path $root 'tools/cc-1c-skills' }
$ProjectDir = [System.IO.Path]::GetFullPath($ProjectDir)
$ToolRoot = [System.IO.Path]::GetFullPath($ToolRoot)

$localBuilder = Join-Path $ToolRoot '.codex/skills/epf-build/scripts/epf-build.ps1'
if (Test-Path $localBuilder -PathType Leaf) {
    $targetSkills = Join-Path $ProjectDir '.codex/skills'
    New-Item -ItemType Directory -Force -Path $targetSkills | Out-Null
    Copy-Item -Path (Join-Path $ToolRoot '.codex/skills/epf-build') -Destination $targetSkills -Recurse -Force
    $installedBuilder = Join-Path $ProjectDir '.codex/skills/epf-build/scripts/epf-build.ps1'
    if (Test-Path $installedBuilder -PathType Leaf) {
        Write-Host ("[OK] cc-1c-skills {0} installed from local checkout" -f $Ref)
        exit 0
    }
    Write-Host 'failed: the local Codex EPF build skill could not be installed.' -ForegroundColor Red
    exit 1
}

$git = Get-Command git -ErrorAction SilentlyContinue
$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $git) {
    Write-Host 'blocked: git is required to obtain the pinned cc-1c-skills revision.' -ForegroundColor Yellow
    exit 2
}
if ($null -eq $python) {
    Write-Host 'blocked: Python is required by the official cc-1c-skills switch.py installer.' -ForegroundColor Yellow
    exit 2
}

if (-not (Test-Path (Join-Path $ToolRoot '.git'))) {
    if (Test-Path $ToolRoot) { Remove-Item -Path $ToolRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ToolRoot) | Out-Null
    & $git.Source clone --no-checkout $Repository $ToolRoot
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'blocked: cc-1c-skills could not be cloned.' -ForegroundColor Yellow
        exit 2
    }
}

& $git.Source -C $ToolRoot fetch --depth 1 origin $Ref
if ($LASTEXITCODE -ne 0) {
    Write-Host ("blocked: pinned cc-1c-skills revision could not be fetched: {0}" -f $Ref) -ForegroundColor Yellow
    exit 2
}
& $git.Source -C $ToolRoot checkout --detach FETCH_HEAD
if ($LASTEXITCODE -ne 0) {
    Write-Host 'failed: cc-1c-skills checkout failed.' -ForegroundColor Red
    exit 1
}

$switchScript = Join-Path $ToolRoot 'scripts/switch.py'
if (-not (Test-Path $switchScript -PathType Leaf)) {
    Write-Host 'failed: the pinned cc-1c-skills revision has no official switch.py.' -ForegroundColor Red
    exit 1
}

& $python.Source $switchScript codex --runtime powershell --project-dir $ProjectDir
if ($LASTEXITCODE -ne 0) {
    Write-Host 'failed: the official cc-1c-skills Codex installation did not complete.' -ForegroundColor Red
    exit 1
}

$builder = Join-Path $ProjectDir '.codex/skills/epf-build/scripts/epf-build.ps1'
if (-not (Test-Path $builder -PathType Leaf)) {
    Write-Host 'failed: the Codex EPF build skill was not installed.' -ForegroundColor Red
    exit 1
}
Write-Host ("[OK] cc-1c-skills {0} installed in .codex/skills/" -f $Ref)
exit 0
