@set CMD_LC_ROOT=%~dp0
@cd /d "%CMD_LC_ROOT%"
@call common.cmd
@call build_version.cmd
@cd /d "%CMD_LC_ROOT%"

@set targetpath=%mapfolder%\%mapfile%

@if not exist "%targetpath%" @mkdir "%targetpath%"

@rem # Can we do this somehow better?
@if not exist "%targetpath%\maps" @mkdir "%targetpath%\maps"
@if not exist "%targetpath%\addon.json" (
	@echo File "%targetpath%\addon.json" does not exist!
	@goto fail
)

@del /S /Q "%targetpath%\maps\*.bsp"
@del /S /Q "%targetpath%\maps\*.nav"
@del /S /Q "%targetpath%\maps\*.lmp"
@del /S /Q "%targetpath%\maps\graphs\*.ain"

@echo Uploading %mapname%
@if not exist "%GameDir%\maps\%mapname%.bsp" @(
	@echo Missing map!
	@goto fail
)


copy "%GameDir%\maps\%mapname%.bsp" "%targetpath%\maps\"
@if errorlevel 1 @goto fail


@if %TRIGGER_STRIPPING_HACK_ENABLE%==1 @goto hack_triggerstrip_bundle
@goto hack_triggerstrip_skip_bundle

:hack_triggerstrip_bundle
copy "%GameDir%\maps\%mapname%_triggers.lmp" "%targetpath%\maps\"
@if errorlevel 1 @goto fail
copy "%GameDir%\maps\%mapname%_trigmesh.lmp" "%targetpath%\maps\"
@if errorlevel 1 @goto fail


:hack_triggerstrip_skip_bundle

@if exist "%GameDir%\maps\graphs\%mapname%.ain" @(
	@if not exist "%targetpath%\maps\graphs" @mkdir "%targetpath%\maps\graphs"
	copy "%GameDir%\maps\graphs\%mapname%.ain" "%targetpath%\maps\graphs"
)


@if %DONT_PUBLISH_NAV%==1 @goto nocopynav
@if exist "%GameDir%\maps\%mapname%.nav" copy "%GameDir%\maps\%mapname%.nav" "%targetpath%\maps\"
:nocopynav

@if exist "%targetpath%.gma" @del "%targetpath%.gma"

@echo Creating .gma to "%targetpath%.gma"
@echo.
%GameExeDir%/bin/gmad create -folder "%targetpath%" -out "%targetpath%.gma"
@if errorlevel 1 @goto fail

@if not exist "%targetpath%.gma" @goto fail

@if not exist "%targetpath%.jpg" (
	@echo File "%targetpath%.jpg" does not exist!
	@goto fail
)

@set CHANGES=Publishing %mapname%.bsp

@if %mapwsid%==0 @(
	@echo Missing mapwsid, can not publish
	@goto skippublish
)

@echo.
%GameExeDir%/bin/gmpublish update -addon "%targetpath%.gma" -id "%mapwsid%" -changes "%CHANGES%"
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