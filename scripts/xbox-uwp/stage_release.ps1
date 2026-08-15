[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,
    [ValidateSet('Release', 'RelWithDebInfo')]
    [string]$Configuration = 'Release',
    [string]$PackageRoot,
    [string]$OutputRoot,
    [string]$BuildInfo,
    [string]$CertificatePath,
    [string]$CertificatePassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$configurationDirectory = $Configuration.ToLowerInvariant()
if (-not $PackageRoot) {
    $PackageRoot = Join-Path $repositoryRoot "ports\uwp\build\$configurationDirectory\AppPackages\Gen2RecompedUWP"
}
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repositoryRoot 'dist\xbox-uwp'
}

$packageVersion = "$Version.0"
$packageDirectory = Join-Path $PackageRoot "Gen2RecompedUWP_${packageVersion}_x64_Test"
$package = Join-Path $packageDirectory "Gen2RecompedUWP_${packageVersion}_x64.msix"
if (-not (Test-Path -LiteralPath $package -PathType Leaf)) {
    throw "Expected MSIX was not found: $package"
}

function Get-SignTool {
    $kitsRoot = ${env:ProgramFiles(x86)}
    if (-not $kitsRoot) {
        throw 'ProgramFiles(x86) is not defined.'
    }
    $binRoot = Join-Path $kitsRoot 'Windows Kits\10\bin'
    $tool = Get-ChildItem -LiteralPath $binRoot -Filter signtool.exe -File -Recurse |
        Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $tool) {
        throw 'SignTool was not found in the Windows SDK.'
    }
    return $tool.FullName
}

$certificate = $null
if ($CertificatePath) {
    if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
        throw "Signing certificate was not found: $CertificatePath"
    }
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $CertificatePath,
        $CertificatePassword,
        $flags
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($package)
    try {
        $entry = $archive.GetEntry('AppxManifest.xml')
        if (-not $entry) { throw 'AppxManifest.xml is missing from the MSIX.' }
        $reader = [System.IO.StreamReader]::new($entry.Open())
        try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        $archive.Dispose()
    }
    $publisher = $manifest.Package.Identity.Publisher
    if ($publisher -ne $certificate.Subject) {
        throw "Manifest publisher '$publisher' does not match certificate subject '$($certificate.Subject)'."
    }

    $signTool = Get-SignTool
    $signArguments = @('sign', '/fd', 'SHA256', '/f', $CertificatePath)
    if ($CertificatePassword) {
        $signArguments += @('/p', $CertificatePassword)
    }
    $signArguments += $package
    & $signTool @signArguments
    if ($LASTEXITCODE -ne 0) { throw "SignTool failed with exit code $LASTEXITCODE." }
    & $signTool verify /pa $package
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed with exit code $LASTEXITCODE." }
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$stage = Join-Path $OutputRoot 'stage'
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage | Out-Null

$releasePackage = "Gen2Recomped-$Version-xbox-uwp.msix"
Copy-Item -LiteralPath $package -Destination (Join-Path $stage $releasePackage)
$dependencies = Join-Path $packageDirectory 'Dependencies\x64'
if (Test-Path -LiteralPath $dependencies -PathType Container) {
    $dependencyStage = Join-Path $stage 'Dependencies\x64'
    New-Item -ItemType Directory -Path $dependencyStage -Force | Out-Null
    Copy-Item -Path (Join-Path $dependencies '*') -Destination $dependencyStage -Recurse
}
if ($BuildInfo -and (Test-Path -LiteralPath $BuildInfo -PathType Leaf)) {
    Copy-Item -LiteralPath $BuildInfo -Destination (Join-Path $stage 'build-info.json')
}
if ($certificate) {
    [System.IO.File]::WriteAllBytes(
        (Join-Path $stage 'Gen2RecompedUWP.cer'),
        $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    )
}

$install = @"
Gen2Recomped $Version for Xbox Dev Mode

Install the MSIX and any packages under Dependencies through Xbox Device Portal.
The certificate is public and is included only when the package was release-signed.
ROMs, saves and mods are not included.
"@
[System.IO.File]::WriteAllText(
    (Join-Path $stage 'INSTALL.txt'),
    $install,
    [System.Text.UTF8Encoding]::new($false)
)

$archivePath = Join-Path $OutputRoot "Gen2Recomped-$Version-xbox-uwp.zip"
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archivePath -CompressionLevel Optimal
$stream = [System.IO.File]::OpenRead($archivePath)
try {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
} finally {
    $stream.Dispose()
}
[System.IO.File]::WriteAllText(
    "$archivePath.sha256",
    "$hash  $([System.IO.Path]::GetFileName($archivePath))`n",
    [System.Text.UTF8Encoding]::new($false)
)

Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host "Staged $archivePath"
