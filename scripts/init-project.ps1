[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string]$ProjectName,
    [Parameter(Mandatory = $true)][string]$EpfSourcePath,
    [Parameter(Mandatory = $true)][string]$EpfOutputPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$examplePath = Join-Path $root 'config/epf-build.example.json'
$configPath = Join-Path $root 'config/epf-build.json'
if (-not (Test-Path -LiteralPath $examplePath -PathType Leaf)) { throw "Template config not found: $examplePath" }
if ((Test-Path -LiteralPath $configPath -PathType Leaf) -and -not $Force) {
    throw "Configuration already exists: $configPath. Use -Force only when you explicitly intend to replace it."
}
$config = Get-Content -Raw -LiteralPath $examplePath | ConvertFrom-Json
$config.projectName = $ProjectName
$config.sourceFile = $EpfSourcePath
$config.outputFile = $EpfOutputPath
if ($PSCmdlet.ShouldProcess($configPath, 'write project EPF configuration')) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configPath) | Out-Null
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
    Write-Host "Created $configPath for $ProjectName."
}
