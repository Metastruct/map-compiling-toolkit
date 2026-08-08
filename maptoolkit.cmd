@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0maptoolkit.ps1" %*
if errorlevel 1 goto failed
exit /b 0

:failed
echo.
echo ===== Maptoolkit FAILED (exit code %errorlevel%) =====
echo Check the error output above.
echo.
pause
exit /b 1
