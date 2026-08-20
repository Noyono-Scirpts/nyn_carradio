@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

set "PATH=%USERPROFILE%\bin;%PATH%"

set "BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not defined BASH where bash >nul 2>&1 && for /f "delims=" %%I in ('where bash') do (
  set "BASH=%%I"
  goto :run
)

:run
if not defined BASH (
  echo error: Git Bash not found.
  echo Install Git for Windows, then run:
  echo   scripts\release.bat patch
  exit /b 1
)

"%BASH%" "%~dp0release.sh" %*
exit /b %ERRORLEVEL%
