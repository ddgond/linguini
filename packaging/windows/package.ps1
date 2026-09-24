# Windows release: dist\builds\linguini-windows-x86_64.zip
#
#   packaging\windows\package.ps1
#
# 1. Builds static FFmpeg, curl, OpenSSL, Opus and expat with vcpkg
#    (packaging\windows\build-deps.ps1).
# 2. Builds the extension against them with MSVC and the static C runtime, and
#    checks that it links only DLLs that ship with Windows.
# 3. Exports the Godot project with the "Windows" preset.
# 4. Packs the executable, its console wrapper, the extension, a README and the
#    third-party licences.
#
# Needs: git, Python with SCons, Visual Studio 2022 (or its Build Tools) with
# the C++ workload, and a Godot editor with the matching export templates.
#   GODOT            Godot editor (default: godot). Use the _console.exe build
#                    so its output reaches the terminal.
#   GODOT_TEMPLATES  directory containing windows_release_x86_64.exe (default:
#                    Godot's own export_templates directory for this version)
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
$Dist = "$Root\dist"
$Work = "$Dist\windows"
$Lib = "liblinguini.windows.template_release.x86_64.dll"
$Package = "linguini-windows-x86_64"
$Godot = if ($env:GODOT) { $env:GODOT } else { "godot" }

function Step($msg) { Write-Host "`n==> $msg" }
function Invoke-Checked {
    # @(): with one argument left, $rest would be a string, and splatting a
    # string passes its characters.
    $exe, $rest = $args
    $rest = @($rest)
    & $exe @rest
    if ($LASTEXITCODE -ne 0) { throw "$exe failed with exit code $LASTEXITCODE" }
}

Step "Building the static dependencies"
& "$PSScriptRoot\build-deps.ps1"
$env:LINGUINI_DEPS_PREFIX = "$Work\deps\x64-windows-static-release"

Step "Building the extension"
Push-Location $Root
try { Invoke-Checked scons "-j$env:NUMBER_OF_PROCESSORS" platform=windows target=template_release -Q }
finally { Pop-Location }

Step "Checking the extension's runtime dependencies"
# Only DLLs that every Windows install has: nothing from the Visual C++
# redistributable, which the static runtime replaces.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$dumpbin = & $vswhere -latest -products * -find "VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe" | Select-Object -First 1
if (-not $dumpbin) { throw "dumpbin.exe not found; install the Visual Studio C++ workload" }
$needed = & $dumpbin /nologo /dependents "$Root\godot\bin\$Lib" |
    Where-Object { $_ -match '^\s+(\S+\.dll)\s*$' } | ForEach-Object { $Matches[1] }
$needed | ForEach-Object { Write-Host "    $_" }
$unexpected = $needed | Where-Object {
    $_ -match '^(vcruntime|msvcp|concrt|ucrtbase|api-ms-win-crt-)' -or
    -not (Test-Path "$env:SystemRoot\System32\$_")
}
if ($unexpected) { throw "Unexpected dynamic dependencies: $($unexpected -join ', ')" }

Step "Exporting the Godot project"
$godotVersion = (& $Godot --version | Select-Object -Last 1) -replace '^(\d+\.\d+(\.\d+)?\.[a-z]+\d*).*', '$1'
if (-not $env:GODOT_TEMPLATES) {
    $env:GODOT_TEMPLATES = "$env:APPDATA\Godot\export_templates\$godotVersion"
}
if (-not (Test-Path "$env:GODOT_TEMPLATES\windows_release_x86_64.exe")) {
    throw "No windows_release_x86_64.exe template in $env:GODOT_TEMPLATES (Godot $godotVersion)"
}
$templateVersion = if (Test-Path "$env:GODOT_TEMPLATES\version.txt") {
    (Get-Content "$env:GODOT_TEMPLATES\version.txt" -Raw).Trim()
} else { $godotVersion }
if ($templateVersion -ne $godotVersion) {
    throw "Export templates are $templateVersion but Godot is $godotVersion"
}
# Point Godot at the templates through a private data directory, leaving the
# user's own Godot configuration alone. Godot finds it through APPDATA.
$godotData = "$Work\godot-data"
$templatesLink = "$godotData\Godot\export_templates\$godotVersion"
New-Item -ItemType Directory -Force (Split-Path $templatesLink) | Out-Null
if (Test-Path $templatesLink) { (Get-Item $templatesLink).Delete() }
New-Item -ItemType Junction -Path $templatesLink -Target (Resolve-Path $env:GODOT_TEMPLATES).Path | Out-Null
$userAppData = $env:APPDATA
$env:APPDATA = $godotData
try {
    $export = "$Work\export"
    if (Test-Path $export) { Remove-Item -Recurse -Force $export }
    New-Item -ItemType Directory -Force $export | Out-Null
    # Register the extension up front: found mid-scan on a fresh tree, it makes
    # the import crash on exit.
    New-Item -ItemType Directory -Force "$Root\godot\.godot" | Out-Null
    [IO.File]::WriteAllText("$Root\godot\.godot\extension_list.cfg", "res://linguini.gdextension`n")
    & $Godot --headless --path "$Root\godot" --import *> $null
    & $Godot --headless --path "$Root\godot" --export-release "Windows" "$export\Linguini.exe" 2>&1 |
        Where-Object { "$_" -match "ERROR|WARNING" } | ForEach-Object { Write-Host "$_" }
    foreach ($f in "Linguini.exe", "Linguini.console.exe", $Lib) {
        if (-not (Test-Path "$export\$f")) {
            Get-ChildItem $export | Out-Host
            throw "Export failed: expected $f in $export"
        }
    }

    Step "Packing"
    $stage = "$Work\stage\$Package"
    if (Test-Path "$Work\stage") { Remove-Item -Recurse -Force "$Work\stage" }
    New-Item -ItemType Directory -Force "$stage\licenses" | Out-Null
    Copy-Item "$export\Linguini.exe", "$export\Linguini.console.exe", "$export\$Lib" $stage
    Copy-Item "$PSScriptRoot\README.txt" "$stage\README.txt"
    Copy-Item "$Root\LICENSE" "$stage\LICENSE.txt"
    $licenses = [ordered]@{
        "third_party\moonlight-common-c\LICENSE.txt"   = "moonlight-common-c.txt"
        "third_party\moonlight-embedded\LICENSE"       = "moonlight-embedded.txt"
        "third_party\moonlight-common-c\enet\LICENSE"  = "enet.txt"
        "third_party\moonlight-common-c\nanors\LICENSE" = "nanors.txt"
        "third_party\godot-cpp\LICENSE.md"             = "godot-cpp.md"
        "godot\fonts\Nunito-OFL.txt"                   = "font-nunito.txt"
        "godot\fonts\JetBrainsMono-OFL.txt"            = "font-jetbrains-mono.txt"
        "godot\audio\CREDITS.txt"                      = "sounds.txt"
    }
    foreach ($src in $licenses.Keys) { Copy-Item "$Root\$src" "$stage\licenses\$($licenses[$src])" }
    & $Godot --headless --path "$Root\godot" -- --tool=write_licenses "$stage\licenses\godot.txt" *> $null
    if (-not (Test-Path "$stage\licenses\godot.txt")) { throw "Writing Godot's licences failed" }
    # vcpkg keeps each library's licence as share\<port>\copyright.
    Get-ChildItem "$env:LINGUINI_DEPS_PREFIX\share\*\copyright" | ForEach-Object {
        Copy-Item $_.FullName "$stage\licenses\$($_.Directory.Name).txt"
    }
} finally {
    $env:APPDATA = $userAppData
}

New-Item -ItemType Directory -Force "$Dist\builds" | Out-Null
$zip = "$Dist\builds\$Package.zip"
if (Test-Path $zip) { Remove-Item $zip }
# tar.exe (built into Windows 10+): Windows PowerShell's Compress-Archive
# writes entry names with backslashes, which other unzippers mishandle.
Invoke-Checked tar.exe -a -cf $zip -C "$Work\stage" $Package
Write-Host "`nBuilt $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
