@echo off
setlocal enabledelayedexpansion

:: Configuration
set "VERSION_FILE=%~dp0uAppVersion.pas"
set "TEMP_FILE=%~dp0uAppVersion.tmp"

:: 1. Get Standardized Timestamp using ROBOCOPY
for /f "tokens=1-6 delims=/: " %%a in ('robocopy /l /njh /njs " " " " /ns /nc') do (
    set "STAMP=%%a-%%b-%%c %%d:%%e:%%f"
    goto :found_time
)
:found_time

:: 2. Process the file line-by-line
(
for /f "tokens=1* delims=:" %%a in ('findstr /n "^" "%VERSION_FILE%"') do (
    set "line=%%b"
    if not "!line!"=="" (
        :: Check if the line contains BUILD_DATE
        echo !line! | findstr /C:"BUILD_DATE" >nul
        if !errorlevel! == 0 (
            echo   BUILD_DATE  = '%STAMP%';
        ) else (
            echo !line!
        )
    ) else (
        echo.
    )
)
) > "%TEMP_FILE%"

:: 3. Finalize
move /y "%TEMP_FILE%" "%VERSION_FILE%" >nul
echo [SUCCESS] Updated BUILD_DATE to %STAMP% while preserving comments.
