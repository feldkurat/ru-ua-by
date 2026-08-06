@echo off
rem ---------------------------------------------------------------------------
rem  Installs the combined Russian-Ukrainian-Belarusian keyboard layout.
rem  Plain batch - no PowerShell required. Double-click it, or run it from cmd.
rem ---------------------------------------------------------------------------
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================================
echo  Russian-Ukrainian-Belarusian keyboard layout - install
echo ============================================================
echo.

rem --- re-launch elevated if we are not administrator ------------------------
net session >nul 2>&1
if not errorlevel 1 goto :elevated

echo Administrator rights are required. Approve the prompt that follows.
set "_VBS=%TEMP%\ruuaby_elevate_install.vbs"
> "%_VBS%" echo Set sh = CreateObject("Shell.Application")
>>"%_VBS%" echo sh.ShellExecute "%~f0", "", "%~dp0", "runas", 1
cscript //nologo "%_VBS%"
set "_RC=%ERRORLEVEL%"
del "%_VBS%" >nul 2>&1
if not "%_RC%"=="0" (
    echo.
    echo Elevation was cancelled or failed. Nothing was installed.
    echo.
    pause
)
exit /b %_RC%

:elevated

rem --- pick the package matching this machine --------------------------------
set "ARCH="
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "ARCH=amd64"
if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" set "ARCH=amd64"
if /i "%PROCESSOR_ARCHITECTURE%"=="x86" if not defined PROCESSOR_ARCHITEW6432 set "ARCH=i386"

if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    echo ERROR: This is an ARM64 machine.
    echo.
    echo Keyboard layout DLLs must be native to the processor architecture, and
    echo the Microsoft Keyboard Layout Creator cannot build ARM64 layouts, so
    echo neither of these packages is correct here. Installing the x64 package
    echo would register a layout Windows cannot load.
    echo.
    pause
    exit /b 1
)

if not defined ARCH (
    echo ERROR: Unrecognised processor architecture "%PROCESSOR_ARCHITECTURE%".
    echo.
    pause
    exit /b 1
)

set "MSI=%~dp0build\msi\ruuaby_%ARCH%.msi"
if not exist "%MSI%" (
    echo ERROR: Package not found:
    echo   %MSI%
    echo.
    echo Build it first with build.ps1 followed by make-msi.ps1.
    echo.
    pause
    exit /b 1
)

set "LOG=%TEMP%\ruuaby_install.log"
echo Installing %ARCH% package...
echo   %MSI%
echo.

msiexec /i "%MSI%" /qb /l*v "%LOG%"
set "_RC=%ERRORLEVEL%"

if not "%_RC%"=="0" (
    echo.
    echo Install FAILED with code %_RC%.
    echo A verbose log was written to:
    echo   %LOG%
    echo.
    pause
    exit /b %_RC%
)

echo.
echo Layout installed and registered as KLID a0000419.
echo.
echo ------------------------------------------------------------
echo  One more step, and it is per-user rather than machine-wide:
echo ------------------------------------------------------------
echo.
echo Add the layout to your own language bar:
echo.
echo   Settings ^> Time ^& language ^> Language ^& region
echo     ^> Russian ^> Options ^> Add a keyboard
echo     ^> "Russian-Ukrainian-Belarusian"
echo.
echo Then switch layouts with Win+Space.
echo (If it does not show up, sign out and back in.)
echo.
pause
exit /b 0
