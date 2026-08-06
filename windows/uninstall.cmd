@echo off
rem ---------------------------------------------------------------------------
rem  Removes the combined Russian-Ukrainian-Belarusian keyboard layout.
rem  Plain batch - no PowerShell required.
rem ---------------------------------------------------------------------------
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================================
echo  Russian-Ukrainian-Belarusian keyboard layout - uninstall
echo ============================================================
echo.

rem --- re-launch elevated if we are not administrator ------------------------
net session >nul 2>&1
if not errorlevel 1 goto :elevated

echo Administrator rights are required. Approve the prompt that follows.
set "_VBS=%TEMP%\ruuaby_elevate_uninstall.vbs"
> "%_VBS%" echo Set sh = CreateObject("Shell.Application")
>>"%_VBS%" echo sh.ShellExecute "%~f0", "", "%~dp0", "runas", 1
cscript //nologo "%_VBS%"
set "_RC=%ERRORLEVEL%"
del "%_VBS%" >nul 2>&1
if not "%_RC%"=="0" (
    echo.
    echo Elevation was cancelled or failed. Nothing was removed.
    echo.
    pause
)
exit /b %_RC%

:elevated

set "ARCH="
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "ARCH=amd64"
if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" set "ARCH=amd64"
if /i "%PROCESSOR_ARCHITECTURE%"=="x86" if not defined PROCESSOR_ARCHITEW6432 set "ARCH=i386"
if not defined ARCH set "ARCH=amd64"

set "MSI=%~dp0build\msi\ruuaby_%ARCH%.msi"
set "LOG=%TEMP%\ruuaby_uninstall.log"

if not exist "%MSI%" (
    echo Package file not found:
    echo   %MSI%
    echo.
    echo Remove it instead from Settings ^> Apps ^> Installed apps,
    echo entry "Russian-Ukrainian-Belarusian Keyboard Layout".
    echo.
    pause
    exit /b 1
)

echo Removing %ARCH% package...
echo.

msiexec /x "%MSI%" /qb /l*v "%LOG%"
set "_RC=%ERRORLEVEL%"

rem 1605 = this product is not currently installed; treat as already-gone.
if "%_RC%"=="1605" (
    echo.
    echo The layout was not installed - nothing to do.
    echo.
    pause
    exit /b 0
)

if not "%_RC%"=="0" (
    echo.
    echo Uninstall FAILED with code %_RC%.
    echo A verbose log was written to:
    echo   %LOG%
    echo.
    pause
    exit /b %_RC%
)

echo.
echo Layout files and registration removed.
echo.
echo Windows may still list "Russian-Ukrainian-Belarusian" in your language
echo bar until you sign out and back in. To drop it right away, remove the
echo keyboard under:
echo.
echo   Settings ^> Time ^& language ^> Language ^& region
echo     ^> Russian ^> Options
echo.
pause
exit /b 0
