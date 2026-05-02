@echo off
setlocal
set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"
if not exist "%SCRIPT_DIR%node_modules" (
  call npm install
  if errorlevel 1 exit /b %ERRORLEVEL%
)
call npm run electron:build:exe
exit /b %ERRORLEVEL%
