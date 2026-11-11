@echo off
rem ---------------------------------------------------------------------------
rem  find-python.cmd - used by Play-Mystery.cmd and Mystery-Lab.cmd.
rem
rem  Looks for Python 3.10 or newer, in this order:
rem    1. MYSTERY_PYTHON  (full path to python.exe, if you set it yourself)
rem    2. py -3           (the Python launcher that python.org installs)
rem    3. python          (on PATH; the Microsoft Store placeholder fails the check)
rem    4. python3
rem  Sets PY_CMD to a command prefix such as "py -3", or leaves it empty.
rem  Sets PY_TOO_OLD to the version of an older Python it saw, if any.
rem  No setlocal on purpose: the variables are for the calling script.
rem ---------------------------------------------------------------------------
set "PY_CMD="
set "PY_TOO_OLD="
set "PY_CHECK=import sys; sys.exit(0 if sys.version_info[:2] >= (3, 10) else 3)"

if not defined MYSTERY_PYTHON goto :try_py
"%MYSTERY_PYTHON%" -c "%PY_CHECK%" >nul 2>nul
if errorlevel 1 goto :old_custom
set PY_CMD="%MYSTERY_PYTHON%"
goto :eof
:old_custom
call :remember "%MYSTERY_PYTHON%"

:try_py
py -3 -c "%PY_CHECK%" >nul 2>nul
if errorlevel 1 goto :old_py
set "PY_CMD=py -3"
goto :eof
:old_py
call :remember py -3

:try_python
python -c "%PY_CHECK%" >nul 2>nul
if errorlevel 1 goto :old_python
set "PY_CMD=python"
goto :eof
:old_python
call :remember python

:try_python3
python3 -c "%PY_CHECK%" >nul 2>nul
if errorlevel 1 goto :old_python3
set "PY_CMD=python3"
goto :eof
:old_python3
call :remember python3
goto :eof

rem Record the version of a Python that exists but is too old. "python -V" prints
rem "Python 3.8.10"; anything not starting with a digit (such as "'py' is not
rem recognized..." or the Microsoft Store placeholder message) is ignored.
:remember
if defined PY_TOO_OLD goto :eof
set "PY_SEEN="
for /f "tokens=2" %%v in ('call %* -V 2^>^&1') do if not defined PY_SEEN set "PY_SEEN=%%v"
if not defined PY_SEEN goto :eof
set "PY_FIRST=%PY_SEEN:~0,1%"
for %%d in (0 1 2 3 4 5 6 7 8 9) do if "%PY_FIRST%"=="%%d" set "PY_TOO_OLD=%PY_SEEN%"
set "PY_SEEN="
set "PY_FIRST="
goto :eof
