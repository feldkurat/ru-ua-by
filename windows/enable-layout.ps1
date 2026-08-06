<#
.SYNOPSIS
    Adds the installed combined layout to the current user's language bar.

.DESCRIPTION
    Run this WITHOUT elevation, as the user who will actually type with the layout.
    An elevated session would add the layout to the administrator's profile instead.

    install.ps1 must have been run first; this script reads the KLID it recorded.
#>
[CmdletBinding()]
param(
    [string]$Klid,
    # Language the layout is attached to. Must match the language id used at install time.
    [string]$LanguageTag = 'ru'
)

$ErrorActionPreference = 'Stop'

if (-not $Klid) {
    $klidFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) 'build\klid.txt'
    if (-not (Test-Path $klidFile)) { throw "No KLID given and $klidFile not found. Run install.ps1 first." }
    $Klid = (Get-Content $klidFile -Raw).Trim()
}

$langId = $Klid.Substring(4)          # trailing 4 hex digits, e.g. 0419
$tip    = "${langId}:$Klid"

$list = Get-WinUserLanguageList
$lang = $list | Where-Object { $_.LanguageTag -like "$LanguageTag*" } | Select-Object -First 1
if (-not $lang) {
    $list.Add($LanguageTag)
    $lang = $list | Where-Object { $_.LanguageTag -like "$LanguageTag*" } | Select-Object -First 1
}

if ($lang.InputMethodTips -contains $tip) {
    Write-Host "Layout $tip is already in the language list."
} else {
    $lang.InputMethodTips.Add($tip)
    Set-WinUserLanguageList $list -Force
    Write-Host "Added $tip to language '$($lang.LanguageTag)'."
}

Write-Host 'Switch to it with Win+Space (sign out and back in if it does not appear).'
