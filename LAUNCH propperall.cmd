@rem Store current folder
@set CMD_LC_ROOT=%~dp0

@cd /d "%CMD_LC_ROOT%"
@call config.bat
@cd /d "%CMD_LC_ROOT%"
@title Propper Batch Compiler

@set QC_STORAGE=%mapfolder%\propper
@set VBSPNAME=vbsp_propper
@call config.bat
@cd /d "%CMD_LC_ROOT%"

@%VBSPNAME% >nul 2>nul
@if ERRORLEVEL 9009 goto nofound
@goto found


:nofound
@echo ERROR: %VBSPNAME% could not be found.
@pause > nul
@exit 1

:found
@cd /d "%mapfolder%\propper"
@echo.
@for /r %%i in (*.vmf) do @(
	@echo Processing %%i
	@%VBSPNAME% %%i > "%%i.log"
)
@if ERRORLEVEL 1 goto failed
@goto win



:failed
@echo COMPILE FAILURE!

@pause > nul
@goto gtfo



:win
@echo =======================
@echo ====== FINISHED =======
@echo =======================
@pause > nul

@goto gtfo


:gtfo
@echo.