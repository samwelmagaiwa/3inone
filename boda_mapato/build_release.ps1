<#
.SYNOPSIS
    Bumps the app version in pubspec.yaml and builds a release APK.

.DESCRIPTION
    pubspec.yaml's `version:` field is "versionName+buildNumber"
    (e.g. 1.0.0+1). versionName is what users see; buildNumber is the
    internal counter that must strictly increase for Android to accept
    an update install. By default this script just increments
    buildNumber. Pass -BumpPatch / -BumpMinor / -BumpMajor to also bump
    versionName, or -SetVersion to set an exact one.

.EXAMPLE
    .\build_release.ps1
    # 1.0.0+1 -> 1.0.0+2, then builds

.EXAMPLE
    .\build_release.ps1 -BumpPatch
    # 1.0.0+1 -> 1.0.1+2, then builds

.EXAMPLE
    .\build_release.ps1 -SetVersion 2.0.0
    # 1.0.0+1 -> 2.0.0+2, then builds
#>

param(
    [switch]$BumpPatch,
    [switch]$BumpMinor,
    [switch]$BumpMajor,
    [string]$SetVersion
)

$ErrorActionPreference = "Stop"
$pubspecPath = Join-Path $PSScriptRoot "pubspec.yaml"

if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml not found at $pubspecPath"
}

$content = Get-Content $pubspecPath -Raw
$match = [regex]::Match($content, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
if (-not $match.Success) {
    throw "Could not find a 'version: X.Y.Z+N' line in pubspec.yaml"
}

$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value
$build = [int]$match.Groups[4].Value
$oldVersion = "$major.$minor.$patch+$build"

if ($SetVersion) {
    $parts = $SetVersion.Split(".")
    if ($parts.Count -ne 3) { throw "-SetVersion must look like 1.2.3" }
    $major = [int]$parts[0]; $minor = [int]$parts[1]; $patch = [int]$parts[2]
} elseif ($BumpMajor) {
    $major++; $minor = 0; $patch = 0
} elseif ($BumpMinor) {
    $minor++; $patch = 0
} elseif ($BumpPatch) {
    $patch++
}

$build++
$newVersion = "$major.$minor.$patch+$build"

$newContent = [regex]::Replace($content, '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$', "version: $newVersion")
Set-Content -Path $pubspecPath -Value $newContent -NoNewline -Encoding utf8

Write-Host "Version bumped: $oldVersion -> $newVersion" -ForegroundColor Cyan

Push-Location $PSScriptRoot
try {
    Write-Host "`n== flutter clean ==" -ForegroundColor Yellow
    flutter clean
    if ($LASTEXITCODE -ne 0) { throw "flutter clean failed" }

    Write-Host "`n== flutter pub get ==" -ForegroundColor Yellow
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

    Write-Host "`n== flutter build apk --release ==" -ForegroundColor Yellow
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }

    $apkPath = Join-Path $PSScriptRoot "build\app\outputs\flutter-apk\app-release.apk"
    Write-Host "`nBuild succeeded: version $newVersion" -ForegroundColor Green
    if (Test-Path $apkPath) {
        $size = [math]::Round((Get-Item $apkPath).Length / 1MB, 1)
        Write-Host "APK: $apkPath ($size MB)" -ForegroundColor Green
    }
} finally {
    Pop-Location
}
