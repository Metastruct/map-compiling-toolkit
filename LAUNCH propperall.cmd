@rem Store current folder
@set CMD_LC_ROOT=%~dp0

@cd /d "%CMD_LC_ROOT%"
@call common.cmd
@cd /d "%CMD_LC_ROOT%"
@title Propper Batch Compiler

@set QC_STORAGE=%mapfolder%\propper
@mkdir "%QC_STORAGE%" >nul 2>nul

@set VBSPNAME=%CMD_LC_ROOT%\extras\propper\bin\vbsp_propper.exe
@set PROPPER_TARGET=%mapdata%


@call common.cmd
@cd /d "%CMD_LC_ROOT%"

@set GameDir=%CMD_LC_ROOT%\game_compiling\garrysmod
@set GameExeDir=%CMD_LC_ROOT%\game_compiling
@set sourcesdk=%CMD_LC_ROOT%\game_compiling

@set PATH=%CMD_LC_ROOT%\extras\propper\bin;%PATH%
@"%VBSPNAME%" >nul 2>nul
@if ERRORLEVEL 9009 goto nofound


@goto found


:nofound
@echo ERROR: %VBSPNAME% could not be found.
@pause > nul
@exit 1

:found
@cd /d "%mapfolder%\propper"
@echo Directory: %cd%
@echo.
@bash --help > nul
@if ERRORLEVEL 1 @goto nobash

@echo running propperall.sh
@bash propperall.sh
@if ERRORLEVEL 1 @goto failed

@goto :proppered

:nobash
@echo bash not found, running vanilla (slow, no error detection)
@for /r %%i in (*.vmf) do @(
	@echo Processing "%%i"   Log: "%%i.log"
	"%VBSPNAME%" "%%i" 1>"%%i.log"
	@if ERRORLEVEL 1 goto failed
)
:proppered
@for /r %%i in (*.tmp) do @(
	attrib +h "%%i"
)

@echo ====== Copying files also for hammer usage =======
ROBOCOPY "%GameDir%\materials\models\mspropp" "%PROPPER_TARGET%\materials\models\mspropp" /MOV /s /NFL  /NDL /NJS /NJH /NP /is /it
ROBOCOPY "%GameDir%\models\props\metastruct" "%PROPPER_TARGET%\models\props\metastruct" /MOV /s /NFL  /NDL /NJS /NJH /NP /is /it



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
exit 0