param(
    [string]$Configuration = "Release",
    [string]$WindowsSdkVersion = "10.0"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$portRoot = Join-Path $repoRoot "ports\uwp"
$sourceRoot = Join-Path $portRoot "third_party\sdl2\source"
$buildRoot = Join-Path $portRoot "build\sdl2"
$installRoot = Join-Path $portRoot "build\sdl2-install"

cmake --fresh -S $sourceRoot -B $buildRoot `
    -G "Visual Studio 17 2022" -A x64 `
    -DCMAKE_SYSTEM_NAME=WindowsStore `
    "-DCMAKE_SYSTEM_VERSION=$WindowsSdkVersion" `
    "-DCMAKE_INSTALL_PREFIX=$installRoot" `
    -DSDL_SHARED=ON -DSDL_STATIC=OFF `
    -DSDL_OPENGL=OFF -DSDL_OPENGLES=ON -DSDL_VULKAN=OFF
if ($LASTEXITCODE -ne 0) { throw "SDL2 configure failed with exit code $LASTEXITCODE." }

cmake --build $buildRoot --config $Configuration --target INSTALL --parallel
if ($LASTEXITCODE -ne 0) { throw "SDL2 build failed with exit code $LASTEXITCODE." }
