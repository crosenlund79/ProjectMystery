@echo off
rem ---------------------------------------------------------------------------
rem  Mystery-Lab.cmd - double-click to start. Developer tools - shows spoilers.
rem  Needs Python 3.10 or newer. Works from any folder, including paths with spaces.
rem  Set MYSTERY_NO_PAUSE=1 to skip the "press any key" prompts (for automated tests).
rem ---------------------------------------------------------------------------
setlocal EnableExtensions
title Project Mystery Laboratory
cd /d "%~dp0"

if not exist "mystery\launcher.py" goto :no_package
call "%~dp0tools\find-python.cmd"
if not defined PY_CMD goto :no_python

set "PYTHONUTF8=1"
%PY_CMD% -m mystery.launcher lab
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" goto :done
echo.
echo   Project Mystery Laboratory stopped with an error (exit code %RC%).
echo   The message above should say what went wrong.
echo   Your cases and notes are kept in the runs\cases folder.
call :hold
:done
endlocal & exit /b %RC%

:no_python
echo.
echo   Project Mystery Laboratory needs Python 3.10 or newer, and none was found on this computer.
if defined PY_TOO_OLD echo   The newest Python found is %PY_TOO_OLD%, which is too old.
echo.
echo   To install Python:
echo     1. Open https://www.python.org/downloads/windows/
echo        and download the latest "Python 3" installer (64-bit).
echo     2. Run it. On the first screen tick "Add python.exe to PATH",
echo        then click "Install Now".
echo     3. Close this window and double-click Mystery-Lab.cmd again.
echo.
echo   Or type this in a Command Prompt:   winget install -e --id Python.Python.3.12
echo   Python 3.12 from the Microsoft Store works too.
echo.
echo   Installed it already? Close this window and try again. If it still fails, open
echo   Settings, Apps, Advanced app settings, App execution aliases, and switch off the
echo   "python.exe" and "python3.exe" aliases, or set MYSTERY_PYTHON to the full path
echo   of python.exe.
echo.
call :hold
endlocal & exit /b 9009

:no_package
echo.
echo   This launcher must stay in the Project Mystery folder, next to the "mystery" folder.
echo   If you opened it from inside a .zip file, extract the whole archive first
echo   (right-click the .zip, "Extract All..."), then double-click Mystery-Lab.cmd again.
echo.
call :hold
endlocal & exit /b 1

:hold
if defined MYSTERY_NO_PAUSE goto :eof
echo   Press any key to close this window.
pause >nul
goto :eof
