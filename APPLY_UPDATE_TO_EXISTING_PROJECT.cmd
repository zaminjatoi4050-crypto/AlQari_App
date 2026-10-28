@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY_UPDATE_TO_EXISTING_PROJECT.ps1"
if errorlevel 1 (
  echo Update failed. Read the error above.
  pause
  exit /b 1
)
echo.
echo AlQari v1.5.0 update applied. Now inspect git status before committing.
pause
