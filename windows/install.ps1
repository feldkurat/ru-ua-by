<#
.SYNOPSIS
    Registers the combined Russian-Ukrainian-Belarusian keyboard layout with Windows.

.DESCRIPTION
    Copies the compiled layout DLLs into the Windows system directories and creates
    the registry registration under
    HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\<KLID>.

    Must be run from an elevated PowerShell session.
    Afterwards run enable-layout.ps1 (NOT elevated) to add the layout to your own
    language bar, or add it manually via Settings.

.NOTES
    Re-running the script is safe: an existing registration for the same DLL is reused.
#>
[CmdletBinding()]
param(
    [string]$DllName    = 'ruuaby.dll',
    [string]$LayoutText = 'Russian-Ukrainian-Belarusian',
    # Base language the layout is offered under. 0419 = Russian, 0422 = Ukrainian, 0423 = Belarusian.
    [ValidatePattern('^[0-9a-fA-F]{4}$')]
    [string]$LanguageId = '0419'
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'This script must be run from an elevated (Run as administrator) PowerShell session.'
}

$root  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$build = Join-Path $root 'build'
if (-not (Test-Path $build)) {
    throw "Build output not found at $build. Run build.ps1 first."
}

# --- 1. copy the DLLs -------------------------------------------------------
$copies = @()
if ([Environment]::Is64BitOperatingSystem) {
    $copies += ,@((Join-Path $build 'amd64\ruuaby.dll'), (Join-Path $env:windir 'System32'))
    $copies += ,@((Join-Path $build 'wow64\ruuaby.dll'), (Join-Path $env:windir 'SysWOW64'))
} else {
    $copies += ,@((Join-Path $build 'i386\ruuaby.dll'),  (Join-Path $env:windir 'System32'))
}

foreach ($c in $copies) {
    $src = $c[0]; $dstDir = $c[1]
    if (-not (Test-Path $src)) { throw "Missing build output: $src" }
    $dst = Join-Path $dstDir $DllName
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "Installed $dst"
}

# --- 2. find or allocate a KLID --------------------------------------------
$layoutsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts'
$existing   = Get-ChildItem $layoutsKey

$klid = $null
foreach ($k in $existing) {
    $file = (Get-ItemProperty -Path $k.PSPath -Name 'Layout File' -ErrorAction SilentlyContinue).'Layout File'
    if ($file -and $file -ieq $DllName) { $klid = $k.PSChildName; break }
}

if ($klid) {
    Write-Host "Reusing existing registration $klid"
    $layoutId = (Get-ItemProperty -Path (Join-Path $layoutsKey $klid) -Name 'Layout Id' `
                 -ErrorAction SilentlyContinue).'Layout Id'
} else {
    # Custom layouts use a KLID of <nibble><000><language id> with the nibble in a..f.
    $taken = $existing.PSChildName
    foreach ($n in 'a','b','c','d','e','f') {
        $candidate = "$n" + '000' + $LanguageId
        if ($taken -notcontains $candidate) { $klid = $candidate; break }
    }
    if (-not $klid) { throw 'No free custom KLID available for this language id.' }

    # "Layout Id" must be unique across every installed layout.
    $usedIds = @()
    foreach ($k in $existing) {
        $id = (Get-ItemProperty -Path $k.PSPath -Name 'Layout Id' -ErrorAction SilentlyContinue).'Layout Id'
        if ($id) { $usedIds += $id.ToLower() }
    }
    $layoutId = $null
    for ($i = 0x0100; $i -le 0x0fff; $i++) {
        $candidate = '{0:x4}' -f $i
        if ($usedIds -notcontains $candidate) { $layoutId = $candidate; break }
    }
    if (-not $layoutId) { throw 'No free Layout Id available.' }
}

# --- 3. write the registration ---------------------------------------------
$keyPath = Join-Path $layoutsKey $klid
if (-not (Test-Path $keyPath)) { New-Item -Path $keyPath -Force | Out-Null }

New-ItemProperty -Path $keyPath -Name 'Layout File' -Value $DllName    -PropertyType String -Force | Out-Null
New-ItemProperty -Path $keyPath -Name 'Layout Text' -Value $LayoutText -PropertyType String -Force | Out-Null
New-ItemProperty -Path $keyPath -Name 'Layout Id'   -Value $layoutId   -PropertyType String -Force | Out-Null

Set-Content -Path (Join-Path $build 'klid.txt') -Value $klid -Encoding ascii

Write-Host ''
Write-Host "Registered '$LayoutText'"
Write-Host "  KLID      : $klid"
Write-Host "  Layout Id : $layoutId"
Write-Host ''
Write-Host 'Next: run enable-layout.ps1 in a NORMAL (non-elevated) PowerShell session,'
Write-Host 'or add it by hand under Settings > Time & language > Language & region >'
Write-Host '<language> > Options > Add a keyboard.'
