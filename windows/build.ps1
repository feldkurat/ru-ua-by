<#
.SYNOPSIS
    Compiles ruuaby.klc into keyboard layout DLLs using the kbdutool.exe that ships
    with Microsoft Keyboard Layout Creator 1.4.

.DESCRIPTION
    MSKLC's GUI can do the same via File > Load Source File, then
    Project > Build DLL and Setup Package. This script is the headless equivalent
    and produces the raw DLLs (no MSI wrapper) into build\<arch>\.
#>
[CmdletBinding()]
param(
    [string]$Klc = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) 'ruuaby.klc'),
    [string]$OutDir = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) 'build')
)

$ErrorActionPreference = 'Stop'

$kbdutool = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Keyboard Layout Creator 1.4\bin\i386\kbdutool.exe'
if (-not (Test-Path $kbdutool)) {
    $kbdutool = Join-Path $env:ProgramFiles 'Microsoft Keyboard Layout Creator 1.4\bin\i386\kbdutool.exe'
}
if (-not (Test-Path $kbdutool)) {
    throw 'kbdutool.exe not found. Install Microsoft Keyboard Layout Creator 1.4 first.'
}
if (-not (Test-Path $Klc)) { throw "Source layout not found: $Klc" }

# kbdutool always writes ruuaby.dll into the current directory, so each target
# architecture needs its own working directory.
$targets = @(
    @{ Dir = 'src';   Flag = '-s' }   # generated .C/.H/.DEF/.RC, useful for review
    @{ Dir = 'i386';  Flag = '-x' }
    @{ Dir = 'amd64'; Flag = '-m' }
    @{ Dir = 'wow64'; Flag = '-o' }
)

if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }

foreach ($t in $targets) {
    $dir = Join-Path $OutDir $t.Dir
    New-Item -ItemType Directory -Force $dir | Out-Null
    Push-Location $dir
    try {
        & $kbdutool -u -n $t.Flag $Klc | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "kbdutool failed for target $($t.Dir) (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
    Write-Host "Built $($t.Dir)"
}

Get-ChildItem -Recurse -File $OutDir | Select-Object FullName, Length
