@cd /d "%~dp0"
@cd ..
@call config.bat
@cd /d "%~dp0"



copy /Y build_cubemaps.lua "%GameDir%"\lua\autorun\client\build_cubemaps.lua > nul
@if ERRORLEVEL 1 goto fail
copy /Y mapcomp_write_missing.lua "%GameDir%"\lua\autorun\client\mapcomp_write_missing.lua > nul
@if ERRORLEVEL 1 goto fail

@cd /D %GameExeDir%
@If "%1"=="missing" @goto missing
@If "%1"=="cubemaps_ldr" @goto cubemaps_ldr
@If "%1"=="cubemaps_hdr" @goto cubemaps_hdr

@echo "Unknown task: %1"
@exit 1
@goto out

:missing
@rem @taskkill /T /F /IM hl2.exe 2> nul
start /wait /min hl2.exe -game "%SteamGame%" -multirun -w 1024 -h 768 -console -dev -disableluarefresh -insecure -nohltv +map %2 +alias "exitgame quit" +con_nprint_bgalpha writemissing
@goto win

:cubemaps_ldr
@rem @taskkill /T /F /IM hl2.exe 2> nul
start /wait /min hl2.exe -game "%SteamGame%" -multirun -w 1024 -h 768 -console -dev -disableluarefresh -insecure -nohltv +map %2 +alias "exitgame quit" +con_nprint_bgalpha cubemaps +sv_cheats 1 +mat_hdr_level 0 +mat_specular 0
@goto win

:cubemaps_hdr
@rem @taskkill /T /F /IM hl2.exe 2> nul
start /wait /min hl2.exe -game "%SteamGame%" -multirun -w 1024 -h 768 -console -dev -disableluarefresh -insecure -nohltv +map %2 +alias "exitgame quit" +con_nprint_bgalpha cubemaps +sv_cheats 1 +mat_hdr_level 2 +mat_specular 0
@goto win

@goto win
:fail
@echo SUBTASK FAILED
@pause > nul
@goto out

:win
@echo Subtask finished
@goto out

:out
@del "%GameDir%"\lua\autorun\client\build_cubemaps.lua
@del "%GameDir%"\lua\autorun\client\mapcomp_write_missing.lua
