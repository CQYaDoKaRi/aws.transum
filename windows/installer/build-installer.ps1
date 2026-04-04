# AudioTranscriptionSummary Installer Build Script
# Prerequisites:
#   - Visual Studio 2022 Community (with Windows App SDK workload)
#   - Inno Setup 6 (https://jrsoftware.org/isinfo.php)
#   - Windows App Runtime 1.6

param(
    [string]$Configuration = "Release",
    [string]$Platform = "x64"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Join-Path $scriptDir "..\AudioTranscriptionSummary"
$csproj = Join-Path $projectDir "AudioTranscriptionSummary.csproj"

# Find MSBuild
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
if (-not (Test-Path $msbuild)) {
    $msbuild = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
}
if (-not (Test-Path $msbuild)) {
    Write-Error "MSBuild not found. Install Visual Studio 2022 or Build Tools."
    exit 1
}

Write-Host "=== Building AudioTranscriptionSummary ===" -ForegroundColor Cyan
Write-Host "Configuration: $Configuration"
Write-Host "Platform: $Platform"
Write-Host ""

# Clean and build
& $msbuild $csproj /t:Clean,Build /p:Configuration=$Configuration /p:Platform=$Platform /restore /v:m
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed."
    exit 1
}

Write-Host ""
Write-Host "=== Build succeeded ===" -ForegroundColor Green

# Find Inno Setup compiler
$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
    Write-Host ""
    Write-Host "Inno Setup not found at: $iscc" -ForegroundColor Yellow
    Write-Host "To create the installer, install Inno Setup 6 from https://jrsoftware.org/isinfo.php"
    Write-Host "Then run: & '$iscc' '$scriptDir\setup.iss'"
    Write-Host ""
    Write-Host "Build output is at:" -ForegroundColor Cyan
    $buildDir = Join-Path $projectDir "bin\$Platform\$Configuration\net8.0-windows10.0.19041.0"
    Write-Host "  $buildDir"
    exit 0
}

Write-Host ""
Write-Host "=== Creating installer ===" -ForegroundColor Cyan

$issFile = Join-Path $scriptDir "setup.iss"
& $iscc $issFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "Installer creation failed."
    exit 1
}

$outputDir = Join-Path $scriptDir "output"
Write-Host ""
Write-Host "=== Installer created ===" -ForegroundColor Green
Write-Host "Output: $outputDir"
Get-ChildItem $outputDir -Filter "*.exe" | ForEach-Object {
    Write-Host "  $($_.Name) ($([math]::Round($_.Length / 1MB, 1)) MB)"
}
