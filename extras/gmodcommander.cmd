@cd /d "%~dp0"
@cd ..
@call common.cmd
@set GAME_EXE=%GameExeDir%\bin\win64\gmod.exe
@call common.cmd
@cd /d "%~dp0"



@copy /Y build_cubemaps.lua "%GameDir%"\lua\autorun\client\build_cubemaps.lua > nul
@if ERRORLEVEL 1 goto fail

@copy /Y trigger_extract.lua "%GameDir%"\lua\autorun\server\trigger_extract.lua > nul
@if ERRORLEVEL 1 goto fail

@copy /Y gmodcommander.cfg "%GameDir%"\cfg\gmodcommander.cfg > nul
@if ERRORLEVEL 1 goto fail

@copy /Y mapcomp_write_missing.lua "%GameDir%"\lua\autorun\client\mapcomp_write_missing.lua > nul
@if ERRORLEVEL 1 goto fail

@copy /Y navmesh.lua "%GameDir%"\lua\autorun\server\navmesh.lua > nul
@if ERRORLEVEL 1 goto fail

@copy /Y landmark.lua "%GameDir%"\lua\includes\modules\landmark.lua > nul
@if ERRORLEVEL 1 goto fail


@If "%1"=="missing" @goto missing
@If "%1"=="cubemaps_ldr" @goto cubemaps_ldr
@If "%1"=="navmesh" @goto navmesh
@If "%1"=="trigger_extract" @goto trigger_extract
@If "%1"=="cubemaps_hdr" @goto cubemaps_hdr

@echo "ERROR: Unknown task: %1"
@goto out

:missing
start "MAP TOOLKIT: VMT" /D "%GameExeDir%" /wait /min "%GAME_EXE%" -game "%GameDir%" -multirun -disableluarefresh -noworkshop -windowed %GCNOADDONS% -insecure -nohltv -condebug -textmode -toconsole +map %2 +exec gmodcommander +con_nprint_bgalpha writemissing
@goto win

:trigger_extract
start "MAP TOOLKIT: TRIGGERS" /D "%GameExeDir%" /wait /min "%GAME_EXE%" -game "%GameDir%" -multirun -console -noworkshop %GCNOADDONS% -windowed -disableluarefresh -insecure -nohltv -condebug -textmode -toconsole +map %2 +exec gmodcommander +con_nprint_bgalpha trigger_extract
@goto win

:cubemaps_ldr
start "MAP TOOLKIT: LDR" /D "%GameExeDir%" /wait /min "%GAME_EXE%" -game "%GameDir%" -multirun -w 1024 -h 1024 -noworkshop %GCNOADDONS% -windowed -console -disableluarefresh -insecure -nohltv -condebug -toconsole +map %2 +sv_cheats 1 +mat_hdr_level 0 +mat_specular 0 +exec gmodcommander +con_nprint_bgalpha cubemaps
@goto win

:cubemaps_hdr
start "MAP TOOLKIT: HDR" /D "%GameExeDir%" /wait /min "%GAME_EXE%" -game "%GameDir%" -multirun -w 1024 -h 1024 -noworkshop  %GCNOADDONS% -windowed -console -disableluarefresh -insecure -nohltv -condebug -toconsole +map %2 +sv_cheats 1 +mat_hdr_level 2 +mat_specular 0 +exec gmodcommander +con_nprint_bgalpha cubemaps
@goto win

:navmesh
start "MAP TOOLKIT: NAV" /D "%GameExeDir%" /wait /min "%GAME_EXE%" -game "%GameDir%" -multirun -console -noworkshop %GCNOADDONS% -windowed -disableluarefresh -insecure -nohltv -condebug -textmode -toconsole +map %2 +exec gmodcommander +con_nprint_bgalpha navmesh
@goto win

@goto win
:fail
@echo SUBTASK FAILED
@pause > nul
exit 1

:win
@echo Subtask finished
@goto out

:out
@rem @del "%GameDir%"\lua\autorun\client\build_cubemaps.lua
@rem del "%GameDir%"\lua\autorun\client\mapcomp_write_missing.lua
