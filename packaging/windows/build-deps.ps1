# Static FFmpeg, Opus, OpenSSL, curl and expat for the Windows extension.
#
#   packaging\windows\build-deps.ps1              # -> dist\windows\deps\x64-windows-static-release
#
# Builds the libraries in vcpkg.json with vcpkg, statically and against the
# static C runtime (/MT), which is what godot-cpp builds with. The extension
# then links only system DLLs. Point LINGUINI_DEPS_PREFIX at the printed
# prefix before running scons.
#
# vcpkg is pinned to $VcpkgCommit and fetched into dist\windows\vcpkg. Set
# VCPKG_ROOT to use your own checkout instead. The first run builds FFmpeg
# from source and takes a while; later runs reuse vcpkg's binary cache
# (VCPKG_DEFAULT_BINARY_CACHE, default dist\windows\vcpkg-cache).
#
# Needs: git, and Visual Studio 2022 (or its Build Tools) with the C++ workload.
$ErrorActionPreference = "Stop"

$VcpkgCommit = "dc1232a6e05dcc49703091e83743e3b4df9b9b7c"
$Triplet = "x64-windows-static-release"

$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
$Work = "$Root\dist\windows"
New-Item -ItemType Directory -Force $Work | Out-Null

function Invoke-Checked {
    # @(): with one argument left, $rest would be a string, and splatting a
    # string passes its characters.
    $exe, $rest = $args
    $rest = @($rest)
    & $exe @rest
    if ($LASTEXITCODE -ne 0) { throw "$exe failed with exit code $LASTEXITCODE" }
}

$vcpkg = $env:VCPKG_ROOT
if (-not $vcpkg) {
    $vcpkg = "$Work\vcpkg"
    $have = if (Test-Path "$vcpkg\.git") { git -C $vcpkg rev-parse HEAD } else { "" }
    if ($have -ne $VcpkgCommit) {
        Write-Host "==> Fetching vcpkg $VcpkgCommit"
        if (-not (Test-Path "$vcpkg\.git")) { Invoke-Checked git init -q $vcpkg }
        Invoke-Checked git -C $vcpkg fetch -q --depth 1 https://github.com/microsoft/vcpkg.git $VcpkgCommit
        Invoke-Checked git -C $vcpkg checkout -q --force FETCH_HEAD
        Remove-Item -Force -ErrorAction SilentlyContinue "$vcpkg\vcpkg.exe"
    }
}
if (-not (Test-Path "$vcpkg\vcpkg.exe")) {
    Write-Host "==> Bootstrapping vcpkg"
    Invoke-Checked "$vcpkg\bootstrap-vcpkg.bat" -disableMetrics
    if (-not (Test-Path "$vcpkg\vcpkg.exe")) { throw "Bootstrapping vcpkg failed" }
}

if (-not $env:VCPKG_DEFAULT_BINARY_CACHE) {
    $env:VCPKG_DEFAULT_BINARY_CACHE = "$Work\vcpkg-cache"
}
New-Item -ItemType Directory -Force $env:VCPKG_DEFAULT_BINARY_CACHE | Out-Null

Write-Host "==> Building the dependencies ($Triplet)"
Invoke-Checked "$vcpkg\vcpkg.exe" install --triplet $Triplet --disable-metrics `
    "--x-manifest-root=$PSScriptRoot" "--x-install-root=$Work\deps"

$prefix = "$Work\deps\$Triplet"
Write-Host "==> Done: $prefix"
Write-Host "    `$env:LINGUINI_DEPS_PREFIX = `"$prefix`""
