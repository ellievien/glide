# Copies the Microsoft C++ runtime DLLs (msvcp140, vcruntime140, vcruntime140_1)
# that ship next to glide.exe, taken from the Visual Studio redistributable on
# the build machine.
#
# The runtime must be at least as new as the compiler that built the app:
# binaries compiled with MSVC 14.40 (Visual Studio 2022 17.10) or later crash in
# std::mutex::lock at startup when they load an older msvcp140.dll, and Windows
# loads the copy next to the exe before the system one. A fixed copy checked
# into the repository therefore breaks as soon as the build machine's Visual
# Studio is newer (the old 14.36 copy did exactly that), so this takes the
# newest redistributable of every installed Visual Studio instead.
#
# Usage: copy_windows_crt.ps1 -Arch x64 -Destination app\build\windows\x64\runner\Release

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('x64', 'arm64')]
    [string] $Arch,

    [Parameter(Mandatory = $true)]
    [string] $Destination
)

$ErrorActionPreference = 'Stop'

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found at $vswhere; is Visual Studio installed?"
}
$installations = & $vswhere -all -products * -property installationPath
if (-not $installations) {
    throw 'No Visual Studio installation found'
}

# Redist\MSVC holds one folder per toolset version (e.g. 14.50.35710), each with
# <arch>\Microsoft.VC<toolset>.CRT. Folders such as "v143" are not versions.
$crt = $installations |
    ForEach-Object { Get-ChildItem -Directory -Path (Join-Path $_ "VC\Redist\MSVC\*\$Arch\Microsoft.VC*.CRT") -ErrorAction SilentlyContinue } |
    Where-Object { $_.Parent.Parent.Name -match '^\d+(\.\d+)+$' } |
    Sort-Object { [version]$_.Parent.Parent.Name } |
    Select-Object -Last 1
if (-not $crt) {
    throw "No $Arch C++ runtime redistributable found in: $($installations -join ', ')"
}

Write-Host "Copying the C++ runtime $($crt.Parent.Parent.Name) from $($crt.FullName) to $Destination"
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    Copy-Item -Path (Join-Path $crt.FullName $dll) -Destination $Destination
}
