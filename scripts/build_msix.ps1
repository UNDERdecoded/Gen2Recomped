<#
.SYNOPSIS
  Packages an already-built Windows folder into an MSIX for Windows 10/11.

.DESCRIPTION
  "UWP" for a LÖVE game means MSIX + Desktop Bridge, not a true UWP app: LÖVE
  has no UWP backend, and the last community fork of one is years behind
  upstream.  What an MSIX buys instead is everything people actually want from
  UWP -- a signed, versioned, single-file installer; clean install/uninstall
  through Windows' own package manager; per-user install with no admin prompt;
  a real Start menu entry and tile; and eligibility for the Microsoft Store.
  The app inside is the ordinary win64 build, declared runFullTrust.

  Everything here ships with Windows or the Windows SDK.  No LÖVE rebuild is
  needed: this repackages the folder scripts/build.sh already produces.

.PARAMETER Source
  Folder holding the fused .exe and LÖVE's DLLs.  Defaults to the newest
  *-windowsEXE folder or dist/win/ payload in the repo.

.PARAMETER OutFile
  Where to write the .msix.  Defaults to dist/msix/<name>-<version>.msix.

.PARAMETER Version
  Four-part package version (a.b.c.d).  MSIX requires four parts and the
  LAST one must be 0 for Store submission.  Defaults to the game's version
  with a trailing .0.

.PARAMETER Publisher
  The manifest's Identity/@Publisher.  This must match the signing
  certificate's Subject EXACTLY, character for character, or Windows refuses
  to install the package.  Defaults to the self-signed subject below.

.PARAMETER CertPath / CertPassword
  A .pfx to sign with.  Omit both and the package is left unsigned -- useful
  for inspection, but Windows will not install it.  Either way the public
  half is exported next to the .msix as a .cer, because that file is what a
  player must import before Windows will install a sideloaded package.

  This is the path CI uses: ONE long-lived certificate held as a repository
  secret, so every release carries the same signature and a player trusts it
  once, not once per release.

.PARAMETER MakeCert
  Create a self-signed certificate matching -Publisher, sign with it, and
  export the .cer next to the .msix so the machine can trust it.  Fine for a
  one-off local package, but the certificate is BRAND NEW on every run, so
  anyone installing has to trust every build separately.  Use -CertPath for
  anything handed to someone else.

.PARAMETER TimestampUrl
  RFC3161 timestamp server.  A timestamped signature stays valid after the
  signing certificate expires; without one, the day the certificate lapses is
  the day every release ever published stops installing.  Pass "" to skip.

.EXAMPLE
  scripts\build_msix.ps1 -MakeCert
  scripts\build_msix.ps1 -Source .\Gen2Recomped-0.7.0b-windowsEXE -CertPath mycert.pfx -CertPassword (Read-Host -AsSecureString)
#>
[CmdletBinding()]
param(
  [string]$Source,
  [string]$OutFile,
  [string]$Version,
  [string]$Publisher = "CN=Gen2Recomped",
  [string]$DisplayName = "Gen2Recomped",
  [string]$PublisherDisplayName = "UNDERdecodedHD",
  [string]$PackageName = "UNDERdecodedHD.Gen2Recomped",
  [string]$CertPath,
  [System.Security.SecureString]$CertPassword,
  [string]$TimestampUrl = "http://timestamp.digicert.com",
  [switch]$MakeCert
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Say  { param($m) Write-Host "==> $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "warn: $m" -ForegroundColor Yellow }
function Fail { param($m) Write-Host "error: $m" -ForegroundColor Red; exit 1 }

# --------------------------------------------------------------- SDK tools
# MakeAppx and SignTool live under the versioned SDK bin directories; take the
# newest x64 one rather than hardcoding a Windows SDK version.
function Find-SdkTool {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $roots = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
    "${env:ProgramFiles}\Windows Kits\10\bin"
  ) | Where-Object { $_ -and (Test-Path $_) }
  foreach ($r in $roots) {
    $hit = Get-ChildItem -Path $r -Filter $Name -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\x64\\' } |
      Sort-Object FullName -Descending | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

$MakeAppx = Find-SdkTool "MakeAppx.exe"
if (-not $MakeAppx) {
  Fail @"
MakeAppx.exe not found.  Install the Windows SDK (the "Windows SDK Signing
Tools for Desktop Apps" component is enough):
  winget install --id Microsoft.WindowsSDK.10.0.22621
or pick it in the Visual Studio Installer under "Individual components".
"@
}
$SignTool = Find-SdkTool "SignTool.exe"

# --------------------------------------------------------------- source
if (-not $Source) {
  $candidates = @()
  $candidates += Get-ChildItem -Path $Root -Directory -Filter "*windowsEXE*" -ErrorAction SilentlyContinue
  $distWin = Join-Path $Root "dist\win"
  if (Test-Path $distWin) {
    $candidates += Get-ChildItem -Path $distWin -Directory -ErrorAction SilentlyContinue
  }
  $Source = ($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $Source -or -not (Test-Path $Source)) {
  Fail "no Windows build folder found; pass -Source <folder with the .exe and DLLs>, or run scripts/build.sh win first"
}
$Source = (Resolve-Path $Source).Path

$exe = Get-ChildItem -Path $Source -Filter *.exe | Select-Object -First 1
if (-not $exe) { Fail "no .exe in $Source" }
Say "source: $Source ($($exe.Name))"

# --------------------------------------------------------------- version
if (-not $Version) {
  $v = "0.0.0"
  $verFile = Join-Path $Root "src\core\Version.lua"
  if (Test-Path $verFile) {
    $m = Select-String -Path $verFile -Pattern '(\d+)\.(\d+)\.(\d+)' | Select-Object -First 1
    if ($m) { $v = $m.Matches[0].Value }
  }
  $Version = "$v.0"
}
# MSIX is strict here: four parts, all numeric, and the revision must be 0 for
# a Store package.  A "0.7.0b" style suffix has to be dropped, not smuggled in.
if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
  $digits = ($Version -replace '[^0-9.]', '') -split '\.' | Where-Object { $_ -ne '' }
  while ($digits.Count -lt 4) { $digits += '0' }
  $Version = ($digits[0..3]) -join '.'
  Warn "version normalised to $Version (MSIX needs four numeric parts)"
}
Say "version: $Version"

# --------------------------------------------------------------- staging
$Work = Join-Path $Root ".bazinga\work\msix"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force -Path $Work | Out-Null
Copy-Item -Path (Join-Path $Source "*") -Destination $Work -Recurse -Force

# ------------------------------------------------------- tile images
# Windows requires the tiles to exist; it does not require them to be pretty.
# Scale the repo logo with System.Drawing so the script needs nothing beyond
# what ships with Windows.
$assetsDir = Join-Path $Work "Assets"
New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null
$logo = Join-Path $Root "assets\logo\logo.png"
$tiles = @{ "Square44x44Logo.png" = 44; "Square150x150Logo.png" = 150; "StoreLogo.png" = 50 }
if (Test-Path $logo) {
  Add-Type -AssemblyName System.Drawing
  $src = [System.Drawing.Image]::FromFile($logo)
  foreach ($name in $tiles.Keys) {
    $size = $tiles[$name]
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    # letterbox rather than stretch: the logo is not square
    $scale = [Math]::Min($size / $src.Width, $size / $src.Height)
    $w = [int]($src.Width * $scale); $h = [int]($src.Height * $scale)
    $g.DrawImage($src, [int](($size - $w) / 2), [int](($size - $h) / 2), $w, $h)
    $g.Dispose()
    $bmp.Save((Join-Path $assetsDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
  }
  $src.Dispose()
  Say "tiles generated from assets/logo/logo.png"
} else {
  Warn "assets/logo/logo.png missing; writing blank tiles"
  Add-Type -AssemblyName System.Drawing
  foreach ($name in $tiles.Keys) {
    $bmp = New-Object System.Drawing.Bitmap($tiles[$name], $tiles[$name])
    $bmp.Save((Join-Path $assetsDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
  }
}

# ------------------------------------------------------- manifest
# EntryPoint Windows.FullTrustApplication + the runFullTrust capability is what
# makes this a Desktop Bridge package: the exe runs as an ordinary Win32
# process (it needs real file access for ROM import and save slots), and MSIX
# only handles identity, install and update.
$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
    xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
    xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
    xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities">
  <Identity Name="$PackageName"
            Publisher="$Publisher"
            Version="$Version"
            ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$DisplayName</DisplayName>
    <PublisherDisplayName>$PublisherDisplayName</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.22621.0" />
  </Dependencies>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="Game" Executable="$($exe.Name)" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
          DisplayName="$DisplayName"
          Description="$DisplayName"
          BackgroundColor="transparent"
          Square150x150Logo="Assets\Square150x150Logo.png"
          Square44x44Logo="Assets\Square44x44Logo.png" />
    </Application>
  </Applications>
</Package>
"@
$manifestPath = Join-Path $Work "AppxManifest.xml"
[System.IO.File]::WriteAllText($manifestPath, $manifest, (New-Object System.Text.UTF8Encoding($false)))

# ------------------------------------------------------- pack
if (-not $OutFile) {
  $outDir = Join-Path $Root "dist\msix"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $OutFile = Join-Path $outDir "$DisplayName-$Version.msix"
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
if (Test-Path $OutFile) { Remove-Item -Force $OutFile }

Say "packing $OutFile"
& $MakeAppx pack /d $Work /p $OutFile /o
if ($LASTEXITCODE -ne 0) { Fail "MakeAppx failed" }

# ------------------------------------------------------- sign
$cerOut = [System.IO.Path]::ChangeExtension($OutFile, ".cer")
if ($MakeCert) {
  if (-not $SignTool) { Fail "SignTool.exe not found (install the Windows SDK signing tools)" }
  Say "creating a self-signed certificate for $Publisher"
  # The Subject MUST equal Identity/@Publisher exactly or the install fails
  # with 0x800B0100 "no signature was present in the subject".
  $cert = New-SelfSignedCertificate -Type Custom -Subject $Publisher `
    -KeyUsage DigitalSignature -FriendlyName "$DisplayName sideload" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
  $pfx = Join-Path $Work "sideload.pfx"
  $pw = ConvertTo-SecureString -String ([guid]::NewGuid().ToString()) -Force -AsPlainText
  Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $pw | Out-Null
  Export-Certificate -Cert $cert -FilePath $cerOut | Out-Null
  $CertPath = $pfx
  $CertPassword = $pw
}

if ($CertPath) {
  if (-not $SignTool) { Fail "SignTool.exe not found (install the Windows SDK signing tools)" }
  $plain = ""
  if ($CertPassword) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($CertPassword)
    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  }

  # Read the .pfx BEFORE signing, for two reasons that both cost a whole
  # release if skipped.
  if (-not $MakeCert) {
    $signingCert = $null
    try {
      $signingCert = (Get-PfxData -FilePath $CertPath -Password $CertPassword).EndEntityCertificates[0]
    } catch {
      try {
        $signingCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertPath, $plain)
      } catch {
        Fail "could not open $CertPath -- wrong password, or not a .pfx"
      }
    }

    # 1. A Subject that does not match Identity/@Publisher character for
    #    character produces a package that signs cleanly and then refuses to
    #    install.  Catch it here, where the message can name both values,
    #    instead of on a player's machine as a hex code.
    $norm = { param($s) ($s -replace '\s*,\s*', ',').Trim().ToLowerInvariant() }
    if ((& $norm $signingCert.Subject) -ne (& $norm $Publisher)) {
      Fail @"
certificate Subject does not match the manifest Publisher.
  certificate: $($signingCert.Subject)
  manifest   : $Publisher
Re-run with -Publisher '$($signingCert.Subject)', or sign with a certificate
whose Subject is exactly '$Publisher'.
"@
    }

    # 2. An expired certificate signs without complaint and installs nowhere.
    if ($signingCert.NotAfter -lt (Get-Date)) {
      Fail "signing certificate expired on $($signingCert.NotAfter) -- issue a new one and replace the secret"
    }
    $daysLeft = [int]($signingCert.NotAfter - (Get-Date)).TotalDays
    if ($daysLeft -lt 90) {
      Warn "signing certificate expires in $daysLeft days ($($signingCert.NotAfter))"
    }
    Say "signing as $($signingCert.Subject), valid to $($signingCert.NotAfter.ToString('yyyy-MM-dd'))"

    # The public half ships beside the package: a sideloaded MSIX installs
    # only once this file is in the machine's Trusted People store, so a
    # release without it is a release nobody can install.
    [System.IO.File]::WriteAllBytes($cerOut, $signingCert.Export('Cert'))
  } else {
    Say "signing"
  }

  # A timestamp is what keeps already-published releases installable after
  # the certificate expires; without it they all die on the same day.  It
  # needs the network, so a timestamp-server outage must not fail the build --
  # fall back to an untimestamped signature and say so loudly.
  $signed = $false
  if ($TimestampUrl) {
    & $SignTool sign /fd SHA256 /a /f $CertPath /p $plain /tr $TimestampUrl /td SHA256 $OutFile
    if ($LASTEXITCODE -eq 0) { $signed = $true }
    else { Warn "timestamping via $TimestampUrl failed; signing without a timestamp" }
  }
  if (-not $signed) {
    & $SignTool sign /fd SHA256 /a /f $CertPath /p $plain $OutFile
    if ($LASTEXITCODE -ne 0) { Fail "SignTool failed (does the cert Subject match Publisher='$Publisher'?)" }
    if ($TimestampUrl) { Warn "this package's signature will stop validating when the certificate expires" }
  }
} else {
  Warn "package is UNSIGNED; Windows will refuse to install it. Re-run with -MakeCert, or pass -CertPath."
}

Say "done: $OutFile"
Write-Host ""
Write-Host "To install on this machine:" -ForegroundColor Cyan
if (Test-Path $cerOut) {
  # LocalMachine, not CurrentUser: App Installer only consults the machine
  # store, and a certificate imported into the user store yields
  # 0x800B010A -- "the publisher certificate could not be verified".
  # TrustedPeople, not Root: this is an end-entity certificate, not a CA,
  # and trusting it as a root authority weakens the whole machine.
  Write-Host "  1. Trust the certificate once (needs an ELEVATED shell):"
  Write-Host "     Import-Certificate -FilePath `"$cerOut`" -CertStoreLocation Cert:\LocalMachine\TrustedPeople"
  Write-Host "  2. Add-AppxPackage `"$OutFile`""
} else {
  Write-Host "  Add-AppxPackage `"$OutFile`""
}
Write-Host ""
Write-Host "For the Microsoft Store, do NOT use -MakeCert: reserve the name in" -ForegroundColor Cyan
Write-Host "Partner Center, then rerun with -PackageName / -Publisher /" -ForegroundColor Cyan
Write-Host "-PublisherDisplayName copied verbatim from your app's identity page." -ForegroundColor Cyan
