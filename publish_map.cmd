@set CMD_LC_ROOT=%~dp0
@cd /d "%CMD_LC_ROOT%"
@call config.bat
@call build_version.bat
@cd /d "%CMD_LC_ROOT%"

@if not exist "%mapfolder%\%mapfile%" @mkdir "%mapfolder%\%mapfile%"

@rem # Can we do this somehow better?
@if not exist "%mapfolder%\%mapfile%\maps" @mkdir "%mapfolder%\%mapfile%\maps"
@if not exist "%mapfolder%\%mapfile%\addon.json" (
	@echo File "%mapfolder%\%mapfile%\addon.json" does not exist!
	@goto fail
)

@del /S /Q "%mapfolder%\%mapfile%\maps\*.bsp"
@del /S /Q "%mapfolder%\%mapfile%\maps\*.nav"
@del /S /Q "%mapfolder%\%mapfile%\maps\graphs\*.ain"


@if not exist "%GameDir%\maps\%mapname%.bsp" @(
	@echo Missing map!
	@goto fail
)

copy "%GameDir%\maps\%mapname%.bsp" "%mapfolder%\%mapfile%\maps\"
@if errorlevel 1 @goto fail

@if exist "%GameDir%\maps\graphs\%mapname%.ain" @(
	@if not exist "%mapfolder%\%mapfile%\maps\graphs" @mkdir "%mapfolder%\%mapfile%\maps\graphs"
	copy "%GameDir%\maps\graphs\%mapname%.ain" "%mapfolder%\%mapfile%\maps\graphs"
)

@if exist "%GameDir%\maps\%mapname%.nav" copy "%GameDir%\maps\%mapname%.nav" "%mapfolder%\%mapfile%\maps\"

@if exist "%mapfolder%\%mapfile%.gma" @del "%mapfolder%\%mapfile%.gma"

@echo Creating .gma to "%mapfolder%\%mapfile%.gma"
@echo.
%GameExeDir%/bin/gmad create -folder "%mapfolder%\%mapfile%" -out "%mapfolder%\%mapfile%.gma"
@if errorlevel 1 @goto fail

@if not exist "%mapfolder%\%mapfile%.gma" @goto fail

@if not exist "%mapfolder%\%mapfile%.jpg" (
	@echo File "%mapfolder%\%mapfile%.jpg" does not exist!
	@goto fail
)

@set CHANGES=Publishing %mapname%.bsp

@if %mapwsid%==0 @(
	@echo Missing mapwsid, can not publish
	@goto skippublish
)

@echo.
%GameExeDir%/bin/gmpublish update -addon "%mapfolder%\%mapfile%.gma" -id "%mapwsid%" -changes "%CHANGES%"
@if errorlevel 1 @goto fail
:skippublish

@goto win


:fail
@echo PUBLISHING FAILURE!
@goto die

:win
@echo Finished publishing...
@goto die

:die
@pause > nul