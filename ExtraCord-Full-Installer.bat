@echo off
setlocal EnableExtensions DisableDelayedExpansion
color 07
title ExtraCord - Full Installer

for %%I in ("%~dp0.") do set "PROJECT_ROOT=%%~fI"
set "DIST_DIR=%PROJECT_ROOT%\dist"
set "CLI=%DIST_DIR%\Installer\VencordInstallerCli.exe"

if /i "%~1"=="--restore" goto :restore_latest
if not "%~1"=="" goto :usage

echo ========================================================
echo             ExtraCord - Full Installer
echo ========================================================
echo.

if not defined APPDATA (
    echo ERROR: Windows APPDATA is not available.
    goto :failed
)
if not defined LOCALAPPDATA (
    echo ERROR: Windows LOCALAPPDATA is not available.
    goto :failed
)
if not exist "%PROJECT_ROOT%\package.json" (
    echo ERROR: package.json was not found beside this installer.
    goto :failed
)
if not exist "%CLI%" (
    echo ERROR: The local installer CLI is missing:
    echo "%CLI%"
    goto :failed
)

for %%F in (patcher.js preload.js renderer.js renderer.css) do (
    if not exist "%DIST_DIR%\%%F" (
        echo ERROR: A required local build file is missing: "%DIST_DIR%\%%F"
        goto :failed
    )
    for %%S in ("%DIST_DIR%\%%F") do if %%~zS EQU 0 (
        echo ERROR: A required local build file is empty: "%DIST_DIR%\%%F"
        goto :failed
    )
)

"%CLI%" -version >nul 2>&1
if errorlevel 1 (
    echo ERROR: The local installer CLI failed its version check.
    goto :failed
)

set "DATA_DIR=%APPDATA%\ExtraCord"
set "BACKUPS_DIR=%DATA_DIR%\backups"
set "BACKUP_ROOT="
set "DISCORD_COUNT=0"

echo [1/6] Finding Discord installations...
if defined EXTRACORD_DISCORD_PATH (
    if not exist "%EXTRACORD_DISCORD_PATH%\" (
        echo ERROR: EXTRACORD_DISCORD_PATH does not exist.
        goto :failed
    )
    call :backup_branch "Custom" "%EXTRACORD_DISCORD_PATH%"
    if errorlevel 1 goto :failed
) else (
    call :backup_branch "Stable" "%LOCALAPPDATA%\Discord"
    if errorlevel 1 goto :failed
    call :backup_branch "PTB" "%LOCALAPPDATA%\DiscordPTB"
    if errorlevel 1 goto :failed
    call :backup_branch "Canary" "%LOCALAPPDATA%\DiscordCanary"
    if errorlevel 1 goto :failed
)

if "%DISCORD_COUNT%"=="0" (
    echo ERROR: No Discord installation with app.asar was found.
    echo Install Discord first, or set EXTRACORD_DISCORD_PATH to its install folder.
    goto :failed
)

for /f "delims=" %%I in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss-fff" 2^>nul') do set "BACKUP_STAMP=%%I"
if not defined BACKUP_STAMP (
    echo ERROR: Could not create a timestamp for the backup.
    goto :failed
)
set "BACKUP_ROOT=%BACKUPS_DIR%\%BACKUP_STAMP%"
if exist "%BACKUP_ROOT%\" set "BACKUP_ROOT=%BACKUP_ROOT%-%RANDOM%"

mkdir "%BACKUP_ROOT%" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Could not create the backup folder:
    echo "%BACKUP_ROOT%"
    goto :failed
)

echo [2/6] Saving current Discord archives...
set "DISCORD_COUNT=0"
if defined EXTRACORD_DISCORD_PATH (
    call :backup_branch "Custom" "%EXTRACORD_DISCORD_PATH%"
    if errorlevel 1 goto :rollback_failed
) else (
    call :backup_branch "Stable" "%LOCALAPPDATA%\Discord"
    if errorlevel 1 goto :rollback_failed
    call :backup_branch "PTB" "%LOCALAPPDATA%\DiscordPTB"
    if errorlevel 1 goto :rollback_failed
    call :backup_branch "Canary" "%LOCALAPPDATA%\DiscordCanary"
    if errorlevel 1 goto :rollback_failed
)

if "%DISCORD_COUNT%"=="0" (
    echo ERROR: No Discord installation could be backed up.
    goto :rollback_failed
)

echo [3/6] Checking that Discord is closed...
call :close_discord
if errorlevel 1 goto :rollback_failed

echo [4/6] Checking for an existing ExtraCord installation...
set "INSTALL_ERROR=0"
if defined EXTRACORD_DISCORD_PATH (
    call :check_branch "%EXTRACORD_DISCORD_PATH%"
    if errorlevel 1 set "INSTALL_ERROR=1"
) else (
    call :check_branch "%LOCALAPPDATA%\Discord"
    if errorlevel 1 set "INSTALL_ERROR=1"
    call :check_branch "%LOCALAPPDATA%\DiscordPTB"
    if errorlevel 1 set "INSTALL_ERROR=1"
    call :check_branch "%LOCALAPPDATA%\DiscordCanary"
    if errorlevel 1 set "INSTALL_ERROR=1"
)
if not "%INSTALL_ERROR%"=="0" goto :rollback_failed

echo [5/6] Backing up ExtraCord runtime files...
if not exist "%DATA_DIR%\dist\" mkdir "%DATA_DIR%\dist" >nul 2>&1
if not exist "%DATA_DIR%\dist\" (
    echo ERROR: Could not create "%DATA_DIR%\dist".
    goto :rollback_failed
)
mkdir "%BACKUP_ROOT%\Runtime\dist" >nul 2>&1
if errorlevel 1 goto :rollback_failed

for %%F in (patcher.js preload.js renderer.js renderer.css) do (
    if exist "%DATA_DIR%\dist\%%F" (
        copy /b /y "%DATA_DIR%\dist\%%F" "%BACKUP_ROOT%\Runtime\dist\%%F" >nul
        if errorlevel 1 (
            echo ERROR: Could not back up "%DATA_DIR%\dist\%%F".
            goto :rollback_failed
        )
        >>"%BACKUP_ROOT%\runtime.manifest" echo %%F^|1
        if errorlevel 1 (
            echo ERROR: Could not record the backup state for "%%F".
            goto :rollback_failed
        )
    ) else (
        >>"%BACKUP_ROOT%\runtime.manifest" echo %%F^|0
        if errorlevel 1 (
            echo ERROR: Could not record the backup state for "%%F".
            goto :rollback_failed
        )
    )
)

echo Copying this project's local dist files to:
echo "%DATA_DIR%\dist"
for %%F in (patcher.js preload.js renderer.js renderer.css) do (
    copy /b /y "%DIST_DIR%\%%F" "%DATA_DIR%\dist\%%F" >nul
    if errorlevel 1 (
        echo ERROR: Could not copy "%DIST_DIR%\%%F".
        goto :rollback_failed
    )
)

set "EXTRACORD_USER_DATA_DIR=%DATA_DIR%"
set "VENCORD_USER_DATA_DIR=%DATA_DIR%"
set "VENCORD_DEV_INSTALL=1"

echo [6/6] Installing the local ExtraCord build...
set "INSTALL_ERROR=0"
if defined EXTRACORD_DISCORD_PATH (
    call :install_branch "%EXTRACORD_DISCORD_PATH%"
    if errorlevel 1 set "INSTALL_ERROR=1"
) else (
    call :install_branch "%LOCALAPPDATA%\Discord"
    if errorlevel 1 set "INSTALL_ERROR=1"
    call :install_branch "%LOCALAPPDATA%\DiscordPTB"
    if errorlevel 1 set "INSTALL_ERROR=1"
    call :install_branch "%LOCALAPPDATA%\DiscordCanary"
    if errorlevel 1 set "INSTALL_ERROR=1"
)
if not "%INSTALL_ERROR%"=="0" goto :rollback_failed

echo.
echo ========================================================
echo              ExtraCord installation completed
echo ========================================================
echo Discord backups and previous runtime files:
echo "%BACKUP_ROOT%"
echo ExtraCord data and runtime files:
echo "%DATA_DIR%"
echo Your existing settings, themes, and other dist files were not removed.
echo To restore the files from this backup, run:
echo "%~nx0" --restore
echo.
pause
exit /b 0

:backup_branch
set "BRANCH_ROOT=%~2"
if not exist "%BRANCH_ROOT%\" exit /b 0
set "BRANCH_FOUND=0"
for /d %%V in ("%BRANCH_ROOT%\app-*") do (
    if exist "%%~fV\resources\app.asar" (
        set "BRANCH_FOUND=1"
        if defined BACKUP_ROOT (
            call :backup_resource "%%~fV\resources" "%~1" "%%~nxV"
            if errorlevel 1 exit /b 1
        )
    )
)
if "%BRANCH_FOUND%"=="1" set /a DISCORD_COUNT+=1
exit /b 0

:backup_resource
set "RESOURCE_DIR=%~1"
set "RESOURCE_BACKUP=%BACKUP_ROOT%\Discord\%~2\%~3\resources"
set "APP_PRESENT=0"
set "ORIGINAL_PRESENT=0"
mkdir "%RESOURCE_BACKUP%" >nul 2>&1
if errorlevel 1 exit /b 1
if exist "%RESOURCE_DIR%\app.asar" (
    set "APP_PRESENT=1"
    copy /b /y "%RESOURCE_DIR%\app.asar" "%RESOURCE_BACKUP%\app.asar" >nul
    if errorlevel 1 exit /b 1
)
if exist "%RESOURCE_DIR%\_app.asar" (
    set "ORIGINAL_PRESENT=1"
    copy /b /y "%RESOURCE_DIR%\_app.asar" "%RESOURCE_BACKUP%\_app.asar" >nul
    if errorlevel 1 exit /b 1
)
>>"%BACKUP_ROOT%\discord.manifest" echo "%RESOURCE_DIR%"^|%APP_PRESENT%^|%ORIGINAL_PRESENT%^|"%RESOURCE_BACKUP%"
if errorlevel 1 exit /b 1
exit /b 0

:check_branch
set "CHECK_ROOT=%~1"
if not exist "%CHECK_ROOT%\" exit /b 0
call :latest_resource "%CHECK_ROOT%"
if not defined LATEST_RESOURCE exit /b 0
set "CHECK_RESOURCE=%LATEST_RESOURCE%"
call :check_resource
if errorlevel 1 exit /b 1
exit /b 0

:latest_resource
set "LATEST_RESOURCE="
for /d %%V in ("%~1\app-*") do if exist "%%~fV\resources\app.asar" set "LATEST_RESOURCE=%%~fV\resources"
exit /b 0

:check_resource
if not exist "%CHECK_RESOURCE%\_app.asar" exit /b 0
set "EXTRACORD_CHECK_PATH=%CHECK_RESOURCE%\app.asar"
powershell.exe -NoProfile -Command "$b=[IO.File]::ReadAllBytes($env:EXTRACORD_CHECK_PATH);$s=[Text.Encoding]::ASCII.GetString($b);if($b.Length -lt 4096 -and $s -match '(?i)patcher\.js' -and $s -match '(?i)extracord'){exit 0};exit 1" >nul 2>&1
if not errorlevel 1 (
    echo An existing ExtraCord patch was detected. It will be safely uninstalled before reinstalling.
    exit /b 0
)
echo ERROR: "%CHECK_RESOURCE%" has an existing _app.asar backup but is not a recognized ExtraCord loader.
echo No Discord files will be overwritten. Restore or remove the other client modification first.
exit /b 1

:close_discord
set "DISCORD_RUNNING=0"
for %%P in (Discord.exe DiscordPTB.exe DiscordCanary.exe) do (
    tasklist /FI "IMAGENAME eq %%P" /NH 2>nul | find /I "%%P" >nul
    if not errorlevel 1 set "DISCORD_RUNNING=1"
)
if "%DISCORD_RUNNING%"=="0" exit /b 0
echo Discord is currently running. It must close before its app.asar can be changed.
choice /C YN /M "Close Discord now"
if errorlevel 2 exit /b 1
for %%P in (Discord.exe DiscordPTB.exe DiscordCanary.exe) do (
    taskkill /IM %%P >nul 2>&1
)
timeout /t 3 /nobreak >nul
set "DISCORD_RUNNING=0"
for %%P in (Discord.exe DiscordPTB.exe DiscordCanary.exe) do (
    tasklist /FI "IMAGENAME eq %%P" /NH 2>nul | find /I "%%P" >nul
    if not errorlevel 1 set "DISCORD_RUNNING=1"
)
if "%DISCORD_RUNNING%"=="1" (
    echo ERROR: Discord did not close. Close it manually and run the installer again.
    exit /b 1
)
exit /b 0

:install_branch
set "INSTALL_ROOT=%~1"
if not exist "%INSTALL_ROOT%\" exit /b 0
call :latest_resource "%INSTALL_ROOT%"
if not defined LATEST_RESOURCE exit /b 0
set "CHECK_RESOURCE=%LATEST_RESOURCE%"
if exist "%CHECK_RESOURCE%\_app.asar" (
    set "EXTRACORD_CHECK_PATH=%CHECK_RESOURCE%\app.asar"
    powershell.exe -NoProfile -Command "$b=[IO.File]::ReadAllBytes($env:EXTRACORD_CHECK_PATH);$s=[Text.Encoding]::ASCII.GetString($b);if($b.Length -lt 4096 -and $s -match '(?i)patcher\.js' -and $s -match '(?i)extracord'){exit 0};exit 1" >nul 2>&1
    if not errorlevel 1 (
        "%CLI%" -uninstall -location "%INSTALL_ROOT%"
        if errorlevel 1 (
            echo ERROR: Could not remove the previous ExtraCord loader from "%INSTALL_ROOT%".
            exit /b 1
        )
    )
)

:do_install
"%CLI%" -install -location "%INSTALL_ROOT%"
if errorlevel 1 (
    echo ERROR: The local installer CLI failed for "%INSTALL_ROOT%".
    exit /b 1
)
exit /b 0

:restore_latest
echo ========================================================
echo               ExtraCord - Restore
echo ========================================================
echo.
if not defined APPDATA (
    echo ERROR: Windows APPDATA is not available.
    goto :failed
)
set "BACKUPS_DIR=%APPDATA%\ExtraCord\backups"
if not exist "%BACKUPS_DIR%\" (
    echo ERROR: No ExtraCord backups were found.
    goto :failed
)
set "BACKUP_ROOT="
for /f "delims=" %%D in ('dir /b /ad /o:n "%BACKUPS_DIR%" 2^>nul') do if exist "%BACKUPS_DIR%\%%D\discord.manifest" set "BACKUP_ROOT=%BACKUPS_DIR%\%%D"
if not defined BACKUP_ROOT (
    echo ERROR: No ExtraCord backup folder was found.
    goto :failed
)
if not exist "%BACKUP_ROOT%\discord.manifest" (
    echo ERROR: The newest backup is incomplete and has no Discord manifest:
    echo "%BACKUP_ROOT%"
    goto :failed
)
echo Latest backup:
echo "%BACKUP_ROOT%"
echo This restores the saved Discord archives and ExtraCord runtime files.
echo Existing settings, themes, and other data are not deleted.
choice /C YN /M "Continue with restore"
if errorlevel 2 exit /b 1
call :close_discord
if errorlevel 1 goto :failed
call :restore_backup
if errorlevel 1 goto :failed
echo.
echo Restore completed successfully.
echo The backup remains available at "%BACKUP_ROOT%".
pause
exit /b 0

:restore_backup
set "RESTORE_ERROR=0"
for /f "usebackq tokens=1-4 delims=|" %%A in ("%BACKUP_ROOT%\discord.manifest") do (
    call :restore_resource "%%~A" "%%B" "%%C" "%%~D"
    if errorlevel 1 set "RESTORE_ERROR=1"
)
if exist "%BACKUP_ROOT%\runtime.manifest" (
    for /f "usebackq tokens=1,2 delims=|" %%A in ("%BACKUP_ROOT%\runtime.manifest") do (
        call :restore_runtime "%%A" "%%B"
        if errorlevel 1 set "RESTORE_ERROR=1"
    )
)
if not "%RESTORE_ERROR%"=="0" (
    echo ERROR: One or more files could not be restored. The backup has been kept.
    exit /b 1
)
exit /b 0

:restore_resource
set "RESTORE_RES=%~1"
set "RESTORE_APP=%~2"
set "RESTORE_ORIGINAL=%~3"
set "RESTORE_SOURCE=%~4"
if "%RESTORE_APP%"=="1" (
    copy /b /y "%RESTORE_SOURCE%\app.asar" "%RESTORE_RES%\app.asar" >nul
    if errorlevel 1 exit /b 1
) else (
    if exist "%RESTORE_RES%\app.asar" del /f /q "%RESTORE_RES%\app.asar" >nul
    if errorlevel 1 exit /b 1
)
if "%RESTORE_ORIGINAL%"=="1" (
    copy /b /y "%RESTORE_SOURCE%\_app.asar" "%RESTORE_RES%\_app.asar" >nul
    if errorlevel 1 exit /b 1
) else (
    if exist "%RESTORE_RES%\_app.asar" del /f /q "%RESTORE_RES%\_app.asar" >nul
    if errorlevel 1 exit /b 1
)
exit /b 0

:restore_runtime
set "RUNTIME_NAME=%~1"
set "RUNTIME_WAS_PRESENT=%~2"
if not exist "%APPDATA%\ExtraCord\dist\" mkdir "%APPDATA%\ExtraCord\dist" >nul 2>&1
if not exist "%APPDATA%\ExtraCord\dist\" exit /b 1
if "%RUNTIME_WAS_PRESENT%"=="1" (
    copy /b /y "%BACKUP_ROOT%\Runtime\dist\%RUNTIME_NAME%" "%APPDATA%\ExtraCord\dist\%RUNTIME_NAME%" >nul
    if errorlevel 1 exit /b 1
) else (
    if exist "%APPDATA%\ExtraCord\dist\%RUNTIME_NAME%" del /f /q "%APPDATA%\ExtraCord\dist\%RUNTIME_NAME%" >nul
    if errorlevel 1 exit /b 1
)
exit /b 0

:rollback_failed
echo.
echo An error occurred. Restoring the files saved before installation...
call :restore_backup
if errorlevel 1 (
    echo ERROR: Automatic restore was incomplete.
    echo Your backup remains at "%BACKUP_ROOT%".
    goto :failed
)
echo The saved Discord and runtime files were restored.
goto :failed

:usage
echo Usage:
echo   %~nx0
echo   %~nx0 --restore
exit /b 2

:failed
echo.
echo Installation stopped. No project dist files or plugin sources were changed.
pause
exit /b 1
