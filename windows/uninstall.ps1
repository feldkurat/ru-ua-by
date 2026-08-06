<#
.SYNOPSIS
    Removes the combined Russian-Ukrainian-Belarusian layout from Windows.

.DESCRIPTION
    Run enable-layout.ps1's counterpart first if you want it gone from the language
    bar cleanly: this script drops the layout from the current user's language list,
    then (when elevated) removes the registry key and the installed DLLs.
#>
[CmdletBinding()]
param(
    [string]$DllName = 'ruuaby.dll'
)

$ErrorActionPreference = 'Stop'

$layoutsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts'

$klid = $null
foreach ($k in Get-ChildItem $layoutsKey) {
    $file = (Get-ItemProperty -Path $k.PSPath -Name 'Layout File' -ErrorAction SilentlyContinue).'Layout File'
    if ($file -and $file -ieq $DllName) { $klid = $k.PSChildName; break }
}

if (-not $klid) {
    Write-Host "No registration found for $DllName - nothing to do."
    return
}

# Remove from this user's language list (works unelevated; harmless if absent).
$langId = $klid.Substring(4)
$tip    = "${langId}:$klid"
$list   = Get-WinUserLanguageList
$changed = $false
foreach ($lang in $list) {
    if ($lang.InputMethodTips -contains $tip) {
        [void]$lang.InputMethodTips.Remove($tip)
        $changed = $true
    }
}
if ($changed) {
    Set-WinUserLanguageList $list -Force
    Write-Host "Removed $tip from the language list."
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning 'Not elevated: registry key and DLLs were left in place. Re-run as administrator to finish.'
    return
}

Remove-Item -Path (Join-Path $layoutsKey $klid) -Recurse -Force
Write-Host "Removed registry key $klid"

foreach ($dir in @('System32', 'SysWOW64')) {
    $dll = Join-Path (Join-Path $env:windir $dir) $DllName
    if (Test-Path $dll) {
        Remove-Item -LiteralPath $dll -Force
        Write-Host "Deleted $dll"
    }
}
