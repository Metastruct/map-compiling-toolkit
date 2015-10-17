@cd /d "%~dp0"
@cd ..
@call config.bat
@cd /d "%~dp0"



@rem copy /Y build_cubemaps.lua "%GameDir%"\lua\autorun\client\build_cubemaps.lua > nul
@rem @if ERRORLEVEL 1 goto fail
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
start /wait /min hl2.exe -game "%GameDir%" -multirun -w 1024 -h 768 -windowed -console -dev -disableluarefresh -insecure -nohltv +map %2 +alias "exitgame quit" +con_nprint_bgalpha writemissing
@goto win

:cubemaps_ldr
start /wait /min hl2.exe -game "%GameDir%" -multirun -w 1024 -h 768 -windowed -nodev -disableluarefresh -insecure -nohltv +map %2 +sv_cheats 1 +mat_hdr_level 0 +mat_specular 0 -buildcubemaps
@goto win

:cubemaps_hdr
start /wait /min hl2.exe -game "%GameDir%" -multirun -w 1024 -h 768 -windowed -nodev -disableluarefresh -insecure -nohltv +map %2 +sv_cheats 1 +mat_hdr_level 2 +mat_specular 0 -buildcubemaps
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
@rem @del "%GameDir%"\lua\autorun\client\build_cubemaps.lua
@del "%GameDir%"\lua\autorun\client\mapcomp_write_missing.lua
