<#
.SYNOPSIS
    Builds an installable MSI for the combined Russian-Ukrainian-Belarusian
    keyboard layout, one package per architecture.

.DESCRIPTION
    MSKLC can produce a setup package from its GUI (Project > Build DLL and Setup
    Package), but its -build command line switch only opens the GUI, so it cannot be
    driven headlessly. This script authors the MSI directly through the Windows
    Installer automation interface, which needs no toolchain beyond what ships with
    Windows: the layout DLLs go into a cabinet built by makecab.exe, and the
    database is created table by table.

    The resulting package:
      * installs the layout DLL into %WINDIR%\System32 (and SysWOW64 for amd64),
      * registers it under HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts,
      * supports clean uninstall from Apps & features,
      * supports major upgrade, so rebuilding and reinstalling replaces the old one.

    Run build.ps1 first to produce build\<arch>\ruuaby.dll.

.PARAMETER LayoutId
    The unique "Layout Id" written to the registry. Windows requires this to be
    unique among all installed layouts on the target machine. Like MSKLC's own
    setup package, the value is fixed at build time; 0100 is chosen because inbox
    Windows layouts occupy the low range only.
#>
[CmdletBinding()]
param(
    [ValidateSet('amd64', 'i386')]
    [string[]]$Arch = @('amd64', 'i386'),

    [string]$ProductName    = 'Russian-Ukrainian-Belarusian Keyboard Layout',
    [string]$LayoutText     = 'Russian-Ukrainian-Belarusian',
    [string]$Manufacturer   = 'Sevana',
    [string]$ProductVersion = '1.0.0',
    [string]$DllName        = 'ruuaby.dll',

    [ValidatePattern('^[0-9a-f]{8}$')]
    [string]$Klid           = 'a0000419',

    [ValidatePattern('^[0-9a-f]{4}$')]
    [string]$LayoutId       = '0100',

    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

$root   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$build  = Join-Path $root 'build'
if (-not $OutDir) { $OutDir = Join-Path $build 'msi' }

# Stable identity. UpgradeCode and component GUIDs must never change across builds;
# ProductCode is regenerated per build so each rebuild is a major upgrade.
$UpgradeCode = '{6B4A2F1E-9C3D-4A57-8E21-5D7F0B934C18}'
$CompGuid = @{
    amd64_sys64 = '{2F8C5D41-7B3E-4C96-A05F-1E6D8A24B370}'
    amd64_wow64 = '{C41B9E70-5A82-46D3-9F18-3B7C0D25E894}'
    i386_sys32  = '{7D3E1A56-4F09-4B82-B6C7-2A85D419F0E3}'
}

$RegKey = "SYSTEM\CurrentControlSet\Control\Keyboard Layouts\$Klid"

# --- COM helpers -----------------------------------------------------------
# The WindowsInstaller type library does not bind reliably through PowerShell's
# default COM adapter, so every call goes through InvokeMember explicitly.
function Invoke-Com { param($Obj, [string]$Name, [object[]]$Params = @())
    try { $Obj.GetType().InvokeMember($Name, 'InvokeMethod', $null, $Obj, $Params) }
    catch { throw "COM call '$Name' failed: $($_.Exception.InnerException.Message)" }
}
function Get-ComProp { param($Obj, [string]$Name, [object[]]$Params = @())
    try { $Obj.GetType().InvokeMember($Name, 'GetProperty', $null, $Obj, $Params) }
    catch { throw "COM property get '$Name' failed: $($_.Exception.InnerException.Message)" }
}
# SummaryInformation exposes Property as an indexed put, not a SetProperty method.
function Set-SummaryProp { param($Si, [int]$Pid2, $Value)
    try { $Si.GetType().InvokeMember('Property', 'SetProperty', $null, $Si, @($Pid2, $Value)) | Out-Null }
    catch { throw "Summary property $Pid2 failed: $($_.Exception.InnerException.Message)" }
}
function Invoke-Sql { param($Db, [string]$Sql)
    $view = Invoke-Com $Db 'OpenView' @($Sql)
    try {
        Invoke-Com $view 'Execute' @($null) | Out-Null
    } catch {
        throw "SQL failed: $Sql`n$($_.Exception.Message)"
    } finally {
        Invoke-Com $view 'Close' @() | Out-Null
    }
}

# --- cabinet ---------------------------------------------------------------
function New-LayoutCab {
    param([hashtable[]]$Files, [string]$CabPath)

    $work = Join-Path ([IO.Path]::GetTempPath()) ("ruuaby_cab_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $work | Out-Null
    try {
        $ddf = @(
            '.OPTION EXPLICIT'
            '.Set CabinetNameTemplate=out.cab'
            ".Set DiskDirectory1=`"$work`""
            '.Set Cabinet=on'
            '.Set Compress=on'
            '.Set CompressionType=MSZIP'
            '.Set MaxDiskSize=0'
            '.Set ReservePerCabinetSize=0'
            '.Set InfFileName=NUL'
            '.Set RptFileName=NUL'
        )
        # The member name inside the cab must equal the File table key.
        foreach ($f in $Files) { $ddf += "`"$($f.Source)`" `"$($f.Key)`"" }

        $ddfPath = Join-Path $work 'files.ddf'
        Set-Content -LiteralPath $ddfPath -Value $ddf -Encoding ascii

        $log = & makecab.exe /F $ddfPath 2>&1
        $made = Join-Path $work 'out.cab'
        if (-not (Test-Path $made)) { throw "makecab failed:`n$($log -join "`n")" }

        Copy-Item -LiteralPath $made -Destination $CabPath -Force
    } finally {
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    }
}

# --- database schema -------------------------------------------------------
$Schema = @(
    "CREATE TABLE ``Property`` (``Property`` CHAR(72) NOT NULL, ``Value`` LONGCHAR NOT NULL LOCALIZABLE PRIMARY KEY ``Property``)"
    "CREATE TABLE ``Directory`` (``Directory`` CHAR(72) NOT NULL, ``Directory_Parent`` CHAR(72), ``DefaultDir`` CHAR(255) NOT NULL LOCALIZABLE PRIMARY KEY ``Directory``)"
    "CREATE TABLE ``Component`` (``Component`` CHAR(72) NOT NULL, ``ComponentId`` CHAR(38), ``Directory_`` CHAR(72) NOT NULL, ``Attributes`` SHORT NOT NULL, ``Condition`` CHAR(255), ``KeyPath`` CHAR(72) PRIMARY KEY ``Component``)"
    "CREATE TABLE ``Feature`` (``Feature`` CHAR(38) NOT NULL, ``Feature_Parent`` CHAR(38), ``Title`` CHAR(64) LOCALIZABLE, ``Description`` CHAR(255) LOCALIZABLE, ``Display`` SHORT, ``Level`` SHORT NOT NULL, ``Directory_`` CHAR(72), ``Attributes`` SHORT NOT NULL PRIMARY KEY ``Feature``)"
    "CREATE TABLE ``FeatureComponents`` (``Feature_`` CHAR(38) NOT NULL, ``Component_`` CHAR(72) NOT NULL PRIMARY KEY ``Feature_``, ``Component_``)"
    "CREATE TABLE ``File`` (``File`` CHAR(72) NOT NULL, ``Component_`` CHAR(72) NOT NULL, ``FileName`` CHAR(255) NOT NULL LOCALIZABLE, ``FileSize`` LONG NOT NULL, ``Version`` CHAR(72), ``Language`` CHAR(20), ``Attributes`` SHORT, ``Sequence`` LONG NOT NULL PRIMARY KEY ``File``)"
    "CREATE TABLE ``Media`` (``DiskId`` SHORT NOT NULL, ``LastSequence`` LONG NOT NULL, ``DiskPrompt`` CHAR(64) LOCALIZABLE, ``Cabinet`` CHAR(255), ``VolumeLabel`` CHAR(32), ``Source`` CHAR(72) PRIMARY KEY ``DiskId``)"
    "CREATE TABLE ``Registry`` (``Registry`` CHAR(72) NOT NULL, ``Root`` SHORT NOT NULL, ``Key`` CHAR(255) NOT NULL LOCALIZABLE, ``Name`` CHAR(255) LOCALIZABLE, ``Value`` LONGCHAR LOCALIZABLE, ``Component_`` CHAR(72) NOT NULL PRIMARY KEY ``Registry``)"
    "CREATE TABLE ``Upgrade`` (``UpgradeCode`` CHAR(38) NOT NULL, ``VersionMin`` CHAR(20), ``VersionMax`` CHAR(20), ``Language`` CHAR(255), ``Attributes`` LONG NOT NULL, ``Remove`` CHAR(255), ``ActionProperty`` CHAR(72) NOT NULL PRIMARY KEY ``UpgradeCode``, ``VersionMin``, ``VersionMax``, ``Language``, ``Attributes``)"
    "CREATE TABLE ``InstallExecuteSequence`` (``Action`` CHAR(72) NOT NULL, ``Condition`` CHAR(255), ``Sequence`` SHORT PRIMARY KEY ``Action``)"
    "CREATE TABLE ``InstallUISequence`` (``Action`` CHAR(72) NOT NULL, ``Condition`` CHAR(255), ``Sequence`` SHORT PRIMARY KEY ``Action``)"
    "CREATE TABLE ``AdminExecuteSequence`` (``Action`` CHAR(72) NOT NULL, ``Condition`` CHAR(255), ``Sequence`` SHORT PRIMARY KEY ``Action``)"
    "CREATE TABLE ``AdminUISequence`` (``Action`` CHAR(72) NOT NULL, ``Condition`` CHAR(255), ``Sequence`` SHORT PRIMARY KEY ``Action``)"
    "CREATE TABLE ``AdvtExecuteSequence`` (``Action`` CHAR(72) NOT NULL, ``Condition`` CHAR(255), ``Sequence`` SHORT PRIMARY KEY ``Action``)"
)

# Standard action sequences. RemoveExistingProducts sits right after
# InstallInitialize so a rebuild cleanly replaces the previously installed layout.
$InstallExecute = @(
    @{ A = 'FindRelatedProducts';   S = 25 }
    @{ A = 'CostInitialize';        S = 800 }
    @{ A = 'FileCost';              S = 900 }
    @{ A = 'CostFinalize';          S = 1000 }
    @{ A = 'InstallValidate';       S = 1400 }
    @{ A = 'InstallInitialize';     S = 1500 }
    @{ A = 'RemoveExistingProducts';S = 1525 }
    @{ A = 'ProcessComponents';     S = 1600 }
    @{ A = 'UnpublishFeatures';     S = 1800 }
    @{ A = 'RemoveRegistryValues';  S = 2600 }
    @{ A = 'RemoveFiles';           S = 3500 }
    @{ A = 'InstallFiles';          S = 4000 }
    @{ A = 'WriteRegistryValues';   S = 5000 }
    @{ A = 'RegisterProduct';       S = 6100 }
    @{ A = 'PublishFeatures';       S = 6300 }
    @{ A = 'PublishProduct';        S = 6400 }
    @{ A = 'InstallFinalize';       S = 6600 }
)
$InstallUI = @(
    @{ A = 'FindRelatedProducts'; S = 25 }
    @{ A = 'CostInitialize';      S = 800 }
    @{ A = 'FileCost';            S = 900 }
    @{ A = 'CostFinalize';        S = 1000 }
    @{ A = 'ExecuteAction';       S = 1300 }
)
# Populated so `msiexec /a` can extract the payload without installing anything -
# handy for verifying a build.
$AdminExecute = @(
    @{ A = 'CostInitialize';      S = 800 }
    @{ A = 'FileCost';            S = 900 }
    @{ A = 'CostFinalize';        S = 1000 }
    @{ A = 'InstallValidate';     S = 1400 }
    @{ A = 'InstallInitialize';   S = 1500 }
    @{ A = 'InstallAdminPackage'; S = 3900 }
    @{ A = 'InstallFiles';        S = 4000 }
    @{ A = 'InstallFinalize';     S = 6600 }
)
$AdminUI = @(
    @{ A = 'CostInitialize'; S = 800 }
    @{ A = 'FileCost';       S = 900 }
    @{ A = 'CostFinalize';   S = 1000 }
    @{ A = 'ExecuteAction';  S = 1300 }
)

function New-LayoutMsi {
    param([string]$Architecture, [string]$MsiPath)

    # ---- payload for this architecture ----
    if ($Architecture -eq 'amd64') {
        $template = 'x64;1033'
        $schemaVersion = 200
        $files = @(
            @{ Key = 'kbd64'; Source = (Join-Path $build 'amd64\ruuaby.dll'); Dir = 'System64Folder'
               Comp = 'Cmp64'; Guid = $CompGuid.amd64_sys64; CompAttr = 256 }   # 256 = 64-bit component
            @{ Key = 'kbd32'; Source = (Join-Path $build 'wow64\ruuaby.dll'); Dir = 'SystemFolder'
               Comp = 'Cmp32'; Guid = $CompGuid.amd64_wow64; CompAttr = 0 }
        )
        $regComp = 'Cmp64'
    } else {
        $template = 'Intel;1033'
        $schemaVersion = 200
        $files = @(
            @{ Key = 'kbd32'; Source = (Join-Path $build 'i386\ruuaby.dll'); Dir = 'SystemFolder'
               Comp = 'Cmp32'; Guid = $CompGuid.i386_sys32; CompAttr = 0 }
        )
        $regComp = 'Cmp32'
    }

    foreach ($f in $files) {
        if (-not (Test-Path $f.Source)) { throw "Missing build output: $($f.Source). Run build.ps1 first." }
    }

    if (Test-Path $MsiPath) { Remove-Item -LiteralPath $MsiPath -Force }
    $cabPath = [IO.Path]::ChangeExtension($MsiPath, '.cab')
    New-LayoutCab -Files $files -CabPath $cabPath

    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db = Invoke-Com $installer 'OpenDatabase' @($MsiPath, 3)   # 3 = msiOpenDatabaseModeCreate

    try {
        # The _Validation table is not required to install, but a package that
        # carries it is well formed enough for ICE validation tools. MSKLC ships the
        # canonical _Validation.idt, so use it when MSKLC is present and skip it
        # otherwise. Import binds only through the default COM adapter, not
        # through InvokeMember.
        $incDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Keyboard Layout Creator 1.4\inc'
        if (-not (Test-Path (Join-Path $incDir '_Validation.idt'))) {
            $incDir = Join-Path $env:ProgramFiles 'Microsoft Keyboard Layout Creator 1.4\inc'
        }
        if (Test-Path (Join-Path $incDir '_Validation.idt')) {
            try { $db.Import($incDir, '_Validation.idt') }
            catch { Write-Warning "Could not import _Validation.idt: $($_.Exception.InnerException.Message)" }
        } else {
            Write-Warning '_Validation.idt not found; package will omit the _Validation table.'
        }

        foreach ($sql in $Schema) { Invoke-Sql $db $sql }

        # ---- Property ----
        $productCode = '{' + [Guid]::NewGuid().ToString().ToUpper() + '}'
        $props = [ordered]@{
            'ProductCode'          = $productCode
            'ProductName'          = "$ProductName ($Architecture)"
            'ProductVersion'       = $ProductVersion
            'ProductLanguage'      = '1033'
            'Manufacturer'         = $Manufacturer
            'UpgradeCode'          = $UpgradeCode
            'ALLUSERS'             = '1'
            'SecureCustomProperties' = 'OLDVERSIONFOUND'
            'ARPNOMODIFY'          = '1'
            'ARPNOREPAIR'          = '1'
            'ARPCOMMENTS'          = 'Combined Russian, Ukrainian and Belarusian keyboard layout.'
        }
        foreach ($k in $props.Keys) {
            Invoke-Sql $db "INSERT INTO ``Property`` (``Property``,``Value``) VALUES ('$k','$($props[$k])')"
        }

        # ---- Directory ----
        # SystemFolder always resolves to the 32-bit system directory (SysWOW64 on
        # x64); System64Folder resolves to the native System32.
        Invoke-Sql $db "INSERT INTO ``Directory`` (``Directory``,``Directory_Parent``,``DefaultDir``) VALUES ('TARGETDIR','','SourceDir')"
        $dirs = $files.Dir | Select-Object -Unique
        foreach ($d in $dirs) {
            Invoke-Sql $db "INSERT INTO ``Directory`` (``Directory``,``Directory_Parent``,``DefaultDir``) VALUES ('$d','TARGETDIR','.')"
        }

        # ---- Component / File ----
        $seq = 0
        foreach ($f in $files) {
            Invoke-Sql $db ("INSERT INTO ``Component`` (``Component``,``ComponentId``,``Directory_``,``Attributes``,``KeyPath``) " +
                            "VALUES ('$($f.Comp)','$($f.Guid)','$($f.Dir)',$($f.CompAttr),'$($f.Key)')")
            Invoke-Sql $db "INSERT INTO ``FeatureComponents`` (``Feature_``,``Component_``) VALUES ('MainFeature','$($f.Comp)')"

            $seq++
            $info = Get-Item -LiteralPath $f.Source
            # The MSI Version column only accepts dotted numeric versions. The
            # version resource kbdutool emits reads "1, 0, 3, 40", which Windows
            # Installer rejects with error 2725, so rebuild it from the numeric
            # parts rather than using the raw FileVersion string.
            $vi  = $info.VersionInfo
            $ver = '{0}.{1}.{2}.{3}' -f $vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart, $vi.FilePrivatePart
            if ($ver -eq '0.0.0.0') { $ver = $null }
            $verSql  = if ($ver) { "'$ver'" } else { "''" }
            $langSql = if ($ver) { "'1033'" } else { "''" }
            # 512 = Vital, 16384 = Compressed
            Invoke-Sql $db ("INSERT INTO ``File`` (``File``,``Component_``,``FileName``,``FileSize``,``Version``,``Language``,``Attributes``,``Sequence``) " +
                            "VALUES ('$($f.Key)','$($f.Comp)','$DllName',$($info.Length),$verSql,$langSql,16896,$seq)")
        }

        # ---- Feature ----
        Invoke-Sql $db ("INSERT INTO ``Feature`` (``Feature``,``Feature_Parent``,``Title``,``Description``,``Display``,``Level``,``Directory_``,``Attributes``) " +
                        "VALUES ('MainFeature','','Keyboard layout','$LayoutText keyboard layout',1,1,'TARGETDIR',0)")

        # ---- Registry ----
        $regRows = @(
            @{ Id = 'RegLayoutFile'; Name = 'Layout File'; Value = $DllName }
            @{ Id = 'RegLayoutText'; Name = 'Layout Text'; Value = $LayoutText }
            @{ Id = 'RegLayoutId';   Name = 'Layout Id';   Value = $LayoutId }
        )
        foreach ($r in $regRows) {
            Invoke-Sql $db ("INSERT INTO ``Registry`` (``Registry``,``Root``,``Key``,``Name``,``Value``,``Component_``) " +
                            "VALUES ('$($r.Id)',2,'$RegKey','$($r.Name)','$($r.Value)','$regComp')")
        }

        # ---- Media ----
        Invoke-Sql $db ("INSERT INTO ``Media`` (``DiskId``,``LastSequence``,``Cabinet``) " +
                        "VALUES (1,$seq,'#layout.cab')")

        # ---- Upgrade ----
        Invoke-Sql $db ("INSERT INTO ``Upgrade`` (``UpgradeCode``,``VersionMin``,``VersionMax``,``Attributes``,``ActionProperty``) " +
                        "VALUES ('$UpgradeCode','0.0.0','99.0.0',768,'OLDVERSIONFOUND')")

        # ---- sequences ----
        $seqTables = @{
            'InstallExecuteSequence' = $InstallExecute
            'InstallUISequence'      = $InstallUI
            'AdminExecuteSequence'   = $AdminExecute
            'AdminUISequence'        = $AdminUI
        }
        foreach ($t in $seqTables.Keys) {
            foreach ($a in $seqTables[$t]) {
                Invoke-Sql $db "INSERT INTO ``$t`` (``Action``,``Sequence``) VALUES ('$($a.A)',$($a.S))"
            }
        }

        # ---- embed the cabinet ----
        $rec = Invoke-Com $installer 'CreateRecord' @(1)
        Invoke-Com $rec 'SetStream' @(1, $cabPath) | Out-Null
        $view = Invoke-Com $db 'OpenView' @("INSERT INTO ``_Streams`` (``Name``,``Data``) VALUES ('layout.cab', ?)")
        Invoke-Com $view 'Execute' @($rec) | Out-Null
        Invoke-Com $view 'Close' @() | Out-Null

        # ---- summary information ----
        $si = Get-ComProp $db 'SummaryInformation' @(20)
        Set-SummaryProp $si 1  1252                        # codepage
        Set-SummaryProp $si 2  'Installation Database'     # title
        Set-SummaryProp $si 3  $ProductName                # subject
        Set-SummaryProp $si 4  $Manufacturer               # author
        Set-SummaryProp $si 5  'Installer,MSI,Database'
        Set-SummaryProp $si 6  "Installs the $LayoutText keyboard layout."
        Set-SummaryProp $si 7  $template                   # platform;language
        Set-SummaryProp $si 9  ('{' + [Guid]::NewGuid().ToString().ToUpper() + '}')  # package code
        Set-SummaryProp $si 12 (Get-Date)
        Set-SummaryProp $si 13 (Get-Date)
        Set-SummaryProp $si 14 $schemaVersion
        Set-SummaryProp $si 15 2                           # 2 = payload compressed in cabinet
        Set-SummaryProp $si 19 2                           # read-only recommended
        Invoke-Com $si 'Persist' @() | Out-Null

        Invoke-Com $db 'Commit' @() | Out-Null
    } finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($db)
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($installer)
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        Remove-Item -LiteralPath $cabPath -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Built $MsiPath  ($([math]::Round((Get-Item $MsiPath).Length / 1kb)) KB, ProductCode $productCode)"
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
foreach ($a in $Arch) {
    New-LayoutMsi -Architecture $a -MsiPath (Join-Path $OutDir "ruuaby_$a.msi")
}
