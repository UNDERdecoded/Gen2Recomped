<#
.SYNOPSIS
  Windows-native front end for scripts/build_android.sh.

.DESCRIPTION
  build_android.sh is bash, and its gradle half assumes a Linux JDK. On Windows
  the working split is: run the packaging half through WSL/Git Bash (it only
  needs python3), then drive gradlew.bat with a Windows JDK 17. This script
  does both, and shadow-builds out of a space-free directory because ndk-build
  is GNU make underneath and cannot cope with spaces in the project path.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1
  powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1 -Version 0.0.0
  powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1 -PackageOnly
#>
[CmdletBinding()]
param(
  [string]$Version,
  [switch]$PackageOnly
)

$ErrorActionPreference = 'Stop'

function Say  { param($m) Write-Host "==> $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "warn: $m" -ForegroundColor Yellow }
function Fail { param($m) Write-Host "error: $m" -ForegroundColor Red; exit 1 }

$Root = Split-Path -Parent $PSScriptRoot
$AndroidDir = Join-Path $Root 'mobile\android'

if ($Version -and $Version -notmatch '^\d+\.\d+\.\d+$') {
  Fail "invalid -Version '$Version' (expected X.Y.Z)"
}

# --------------------------------------------------------------- packaging
$shArgs = @('--package-only')
if ($Version) { $shArgs = @('--version', $Version) + $shArgs }

$gitBash = 'C:\Program Files\Git\bin\bash.exe'
if (Test-Path $gitBash) {
  Say 'packaging game.love (Git Bash)'
  & $gitBash -lc "cd '$($Root -replace '\\','/')' && bash scripts/build_android.sh $($shArgs -join ' ')"
} elseif (Get-Command wsl -ErrorAction SilentlyContinue) {
  Say 'packaging game.love (WSL)'
  $wslRoot = '/mnt/' + $Root.Substring(0, 1).ToLower() + ($Root.Substring(2) -replace '\\', '/')
  & wsl -e bash -lc "cd '$wslRoot' && bash scripts/build_android.sh $($shArgs -join ' ')"
} else {
  Fail "no bash found. Install Git for Windows or enable WSL, then rerun.`n  (the packaging half of build_android.sh needs bash + python3)"
}
if ($LASTEXITCODE -ne 0) { Fail "build_android.sh --package-only failed ($LASTEXITCODE)" }

if ($PackageOnly) {
  Say 'package-only: game.love + branding ready under mobile/android/'
  exit 0
}

# --------------------------------------------------------------- toolchain
$jdk = $null
foreach ($c in @(
    $env:JAVA_HOME,
    'C:\Program Files\Android\Android Studio\jbr',
    'C:\Program Files\Java\jdk-17',
    'C:\Program Files\Eclipse Adoptium\jdk-17',
    'C:\Program Files\Microsoft\jdk-17')) {
  if ($c -and (Test-Path (Join-Path $c 'bin\java.exe'))) { $jdk = $c; break }
}
if (-not $jdk) {
  $jdk = Get-ChildItem 'C:\Program Files\Java', 'C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Microsoft' `
    -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'jdk-?17' -and (Test-Path (Join-Path $_.FullName 'bin\java.exe')) } |
    Select-Object -First 1 -ExpandProperty FullName
}
if (-not $jdk) { Fail 'JDK 17 not found. Install it (Android Studio''s bundled JBR works) or set JAVA_HOME.' }
Say "JDK: $jdk"

$sdk = $env:ANDROID_SDK_ROOT
if (-not $sdk) { $sdk = $env:ANDROID_HOME }
if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
if (-not (Test-Path $sdk)) {
  Fail "Android SDK not found. Install it via Android Studio or set ANDROID_SDK_ROOT.`n  Tried: $sdk"
}
Say "SDK: $sdk"
$ndk = '25.2.9519653'
if (-not (Test-Path (Join-Path $sdk "ndk\$ndk"))) {
  Warn "NDK $ndk not found under $sdk\ndk (SDK Manager -> Show Package Details)"
}

# --------------------------------------------------------------- shadow tree
# Keep the shadow on the repo's own drive so a small system drive cannot run
# out of room hosting the NDK output.
$buildDir = $AndroidDir
if ($AndroidDir -match ' ') {
  $buildDir = Join-Path ((Split-Path -Qualifier $Root) + '\') 'gen2recomp-android-shadow'
  Say "path contains spaces (ndk-build cannot handle them); shadow-building in $buildDir"
  robocopy $AndroidDir $buildDir /MIR /XD .gradle build .cxx /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { Fail "robocopy to $buildDir failed ($LASTEXITCODE)" }
}

"sdk.dir=$($sdk -replace '\\', '\\' -replace '^([A-Za-z]):', '$1\:')" |
  Set-Content -Encoding ascii (Join-Path $buildDir 'local.properties')

# --------------------------------------------------------------- gradle
$task = 'assembleEmbedNoRecordDebug'
Say "building APK ($task)"
$env:JAVA_HOME = $jdk
$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_HOME = $sdk
if (-not $env:GRADLE_USER_HOME) {
  $env:GRADLE_USER_HOME = Join-Path ((Split-Path -Qualifier $Root) + '\') 'gen2recomp-gradle-home'
}

& cmd /c "cd /d `"$buildDir`" && gradlew.bat --no-daemon $task"
if ($LASTEXITCODE -ne 0) {
  Fail "gradle $task failed ($LASTEXITCODE).`n  game.love was already written to mobile/android/app/src/embed/assets/`n  Iterate on the payload alone with: -PackageOnly"
}

$outDir = Join-Path $buildDir "app\build\outputs\apk\embedNoRecord\debug"
$apks = Get-ChildItem $outDir -Filter *.apk -ErrorAction SilentlyContinue
if (-not $apks) { Fail "gradle finished but no APK under $outDir" }

$dist = Join-Path $Root 'dist\android\debug'
Remove-Item $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$apks | Copy-Item -Destination $dist
Say "APK -> $dist"
$apks | ForEach-Object { '    {0}  {1:N1} MB' -f $_.Name, ($_.Length / 1MB) }
Say 'done'
