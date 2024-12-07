@set CMD_LC_ROOT=%~dp0
@cd /d "%CMD_LC_ROOT%"
@call common.cmd
@call build_version.cmd
@cd /d "%CMD_LC_ROOT%"

@set TARGET_TMP=%mapfolder%\%mapfile%.temp.delme
@set sourcepath=%mapfolder%\%mapfile%
@set bspzip_gma_path=%GameDir%\maps\%mapname%
@set gma_path=%mapfolder%\%mapfile%.gma

del /s /q "%TARGET_TMP%" >nul
@if not exist "%TARGET_TMP%" @mkdir "%TARGET_TMP%"

robocopy "%bspzip_gma_path%" "%TARGET_TMP%" /NFL /NDL /NJH /NJS /nc /ns /np /S /IS /IT
robocopy "%sourcepath%" "%TARGET_TMP%" /NFL /NDL /NJH /NJS /nc /ns /np /S /IS /IT
@if not exist "%TARGET_TMP%\maps" @mkdir "%TARGET_TMP%\maps"
@if not exist "%TARGET_TMP%\addon.json" (
	@echo File "%TARGET_TMP%\addon.json" does not exist!
	@goto fail
)


@echo %NL% [33m# Uploading %mapname% [0m

@if not exist "%GameDir%\maps\%mapname%.bsp" @(
	@echo Missing map!
	@goto fail
)


copy "%GameDir%\maps\%mapname%.bsp" "%TARGET_TMP%\maps\"
@if errorlevel 1 @goto fail


@if %TRIGGER_STRIPPING_HACK_ENABLE%==1 @goto hack_triggerstrip_bundle
@goto hack_triggerstrip_skip_bundle

:hack_triggerstrip_bundle
copy "%GameDir%\maps\%mapname%_triggers.lmp" "%TARGET_TMP%\maps\"
@if errorlevel 1 @goto fail
copy "%GameDir%\maps\%mapname%_trigmesh.lmp" "%TARGET_TMP%\maps\"
@if errorlevel 1 @goto fail


:hack_triggerstrip_skip_bundle

@if exist "%GameDir%\maps\graphs\%mapname%.ain" @(
	@if not exist "%TARGET_TMP%\maps\graphs" @mkdir "%TARGET_TMP%\maps\graphs"
	copy "%GameDir%\maps\graphs\%mapname%.ain" "%TARGET_TMP%\maps\graphs"
)


@if %DONT_PUBLISH_NAV%==1 @goto nocopynav
@if exist "%GameDir%\maps\%mapname%.nav" copy "%GameDir%\maps\%mapname%.nav" "%TARGET_TMP%\maps\"
:nocopynav

@if exist "%gma_path%" @del "%gma_path%"

@echo Creating .gma to "%gma_path%"
@echo.
%GameExeDir%/bin/gmad create -folder "%TARGET_TMP%" -out "%gma_path%" -warninvalid
@if errorlevel 1 @goto fail

@if not exist "%gma_path%" @goto fail

@if not exist "%sourcepath%.jpg" (
	@echo File "%sourcepath%.jpg" does not exist!
	@goto fail
)

@set CHANGES=Publishing %mapname%.bsp

@if %mapwsid%==0 @(
	@echo Missing mapwsid, can not publish
	@goto skippublish
)

@echo.
%GameExeDir%/bin/gmpublish update -addon "%gma_path%" -id "%mapwsid%" -changes "%CHANGES%"
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