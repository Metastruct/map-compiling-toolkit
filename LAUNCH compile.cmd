@rem ==== DONT MIND ME ====
@set NLM=^


@set NL=^^^%NLM%%NLM%^%NLM%%NLM%
@rem ======================

@set VRADHDR=-softsun 0 -bounce 1
@set VBSPEXTRAS=-notjunc -blocksize 2048
@set VRADLDR=%VRADHDR%
@set TESTBUILD=0
@set AUTO_UPLOAD_MAP=0
@set ORIGFOLDER=%CD%
@rem Store current folder
@set CMD_LC_ROOT=%~dp0

@set maptoolkit_temp_addon=%GameDir%\addons\maptoolkit_temp
@rmdir "%maptoolkit_temp_addon%" 2>nul

@set bspzipexe=%CMD_LC_ROOT%extras\gmazip.py


@cd /d "%CMD_LC_ROOT%"
@call common.cmd
@cd /d "%CMD_LC_ROOT%"
@title Map Batch Compiler

@set compilers_dir=%sourcesdk%\bin

@call build_version.cmd 1
@cd /d "%CMD_LC_ROOT%"
@call common.cmd
@cd /d "%CMD_LC_ROOT%"
@echo %NL% [33m# Version to build: %BUILD_VERSION%[0m
@echo %NL% [33m# In: %mapfile%.vmf[0m
@echo %NL% [33m# Out: %mapname%.bsp[0m

@call build_version.cmd -1
@cd /d "%CMD_LC_ROOT%"
@call common.cmd
@cd /d "%CMD_LC_ROOT%"


@if "%1"=="b" @goto buildnext
@if "%1"=="B" @goto buildnext
@if "%1"=="r" @goto buildprev
@if "%1"=="R" @goto buildprev
@if "%1"=="p" @goto repostproc
@if "%1"=="p" @goto repostproc
@if "%1"=="t" @goto testb
:reask
@echo.
@echo Tasks
@echo    [B]uild
@echo    [R]ebuild previous
@echo    [P]ostprocess previous
@echo    [t]est build system
@set /P DEC="Select task> "
@if %DEC%==b @goto buildnext
@if %DEC%==B @goto buildnext
@if %DEC%==R @goto buildprev
@if %DEC%==r @goto buildprev
@if %DEC%==p @goto repostproc
@if %DEC%==P @goto repostproc
@if %DEC%==t @goto testb
@goto reask

:testb
set TESTBUILD=1
@goto reask


:repostproc
@echo Postprocessing version %BUILD_VERSION%.
@goto reprocess

:buildnext
@cd /d "%CMD_LC_ROOT%"
@call build_version.cmd 1
@cd /d "%CMD_LC_ROOT%"
@call common.cmd
@cd /d "%CMD_LC_ROOT%"


@goto dobuild

:buildprev
@call build_version.cmd
@cd /d "%CMD_LC_ROOT%"
@echo Rebuilding version %BUILD_VERSION%.
@goto dobuild

:dobuild





@echo %NL% [33m# Compiling version '%BUILD_VERSION%' target bsp: "%mapfolder%\%mapname%.bsp"[0m



@echo %NL% [33m# Cleaning up bspzip artefacts and setting up map files/folders... [0m
@rem Clean bspzip before retrying in case we have old files
@del /S /Q "%CMD_LC_ROOT%\bspzip_out.log" 2>nul >nul
@set BSPZIP_GMA_OUT=%GameDir%\maps\%mapname%
@del /S /Q "%BSPZIP_GMA_OUT%" 2>nul >nul
@if not exist "%BSPZIP_GMA_OUT%" @mkdir "%BSPZIP_GMA_OUT%"
mklink /J %maptoolkit_temp_addon% %BSPZIP_GMA_OUT%

@set targetvmf=%mapfolder%\%mapname%.vmf
@set targetrad=%mapfolder%\%mapname%.rad
@set targetvbsp=%VProject%\%mapfile%.vbsp
@COPY "%mapfolder%\%mapfile%.vmf" "%targetvmf%"
@if ERRORLEVEL 1 goto failed
@COPY "%mapfolder%\%mapfile%.rad" "%targetrad%" 2>nul >nul

@rem this has to go where the vbsp thinks vproject is and it's referenced by the root vmf so it has to retain its name
@COPY "%mapfolder%\%mapfile%.vbsp" "%targetvbsp%" 2>nul >nul
@COPY "%mapfolder%\detail_custom.vbsp" "%VProject%\detail_custom.vbsp" 2>nul >nul
@COPY "%mapfolder%\detail.vbsp" "%VProject%\detail.vbsp" 2>nul >nul

@rem ===================================

:vmfii

@echo %NL% [33m# VMF Merging [0m

extras\vmfii "%targetvmf%" "%targetvmf%" --instancedir "%mapfolder%" --fgd "%FGDS%" >> %mapfolder%\%mapname%.log
@if ERRORLEVEL 1 goto failed


@rem ===================================

@if %TRIGGER_STRIPPING_HACK_ENABLE%==1 @goto hack_triggerstrip
@goto hack_triggerstrip_skip

:hack_triggerstrip
@set mapname_trigger=%mapname%_trigger
@echo %NL% [33m# lua_trigger hack stripping from vmf [0m
copy "%targetvmf%" "%mapfolder%\%mapname_trigger%.vmf"
@if ERRORLEVEL 1 goto failed
vlts.exe "%mapfolder%\%mapname_trigger%.vmf" "%targetvmf%"
@if ERRORLEVEL 1 goto failed
"%compilers_dir%\vbsp.exe" -allowdynamicpropsasstatic %VBSPEXTRAS% -leaktest -low "%mapfolder%\%mapname_trigger%"
@if ERRORLEVEL 1 goto failed

@echo %NL% [33m# Generating trigger files in data folder[0m
COPY "%mapfolder%\%mapname_trigger%.bsp" "%GameDir%\maps\%mapname_trigger%.bsp"
@if ERRORLEVEL 1 goto trigger_fail
@cd /d "%CMD_LC_ROOT%"
call extras\gmodcommander.cmd trigger_extract "%mapname_trigger%"
@if ERRORLEVEL 1 goto trigger_fail

COPY "%GameDir%\data\bspdata\%mapname_trigger%\triggers.json" "%GameDir%\maps\%mapname%_triggers.lmp"
@if ERRORLEVEL 1 goto trigger_fail
COPY "%GameDir%\data\bspdata\%mapname_trigger%\trigmesh.json" "%GameDir%\maps\%mapname%_trigmesh.lmp"
@if ERRORLEVEL 1 goto trigger_fail



@goto trigger_ok
:trigger_fail
@cd /d "%CMD_LC_ROOT%"
@echo Trigger extraction failed!
@goto failed
:trigger_ok
:hack_triggerstrip_skip

@cd /d "%CMD_LC_ROOT%"

@rem ==========================

:vbsp

@echo %NL% [33m# VBSP [0m

@echo VProject %VProject%
"%compilers_dir%\vbsp.exe" -allowdynamicpropsasstatic %VBSPEXTRAS% -leaktest -low "%mapfolder%\%mapname%"
@if ERRORLEVEL 1 goto failed

:vvis

@echo %NL% [33m# VVIS[0m
if not %TESTBUILD%==1 "%compilers_dir%\vvis.exe" -low "%mapfolder%\%mapname%"
@if ERRORLEVEL 1 goto failed

:vrad
@if %NOLDR%==1 goto vradhdr

:vradldr

@echo %NL% [33m# VRAD LDR[0m
if not %TESTBUILD%==1 "%compilers_dir%\vrad.exe" -low %VRADLDR% -noskyboxrecurse -ldr "%mapfolder%\%mapname%"
@if ERRORLEVEL 1 goto failed


:vradhdr

@echo %NL% [33m# VRAD HDR[0m
if not %TESTBUILD%==1 "%compilers_dir%\vrad.exe" -low %VRADHDR% -noskyboxrecurse -hdr "%mapfolder%\%mapname%"
@if ERRORLEVEL 1 goto failed


:reprocess

:copy

@echo %NL% [33m# Copying to game[0m
COPY "%mapfolder%\%mapname%.bsp" "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed

:cubemap
@echo %NL% [33m# Deleting default cubemaps[0m
@echo SKIPPED (No longer required)
@rem bspzip -deletecubemaps "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed

:pack
@echo %NL% [33m# Packing required files to map[0m
@cd /d "%CMD_LC_ROOT%"
extras\reslister.exe "--format=bspzip" "%mapfolder%\%mapname%.vmf" "%mapdata%" "%GameDir%\maps\%mapname%.bsp.reslister"
@if ERRORLEVEL 1 goto failed
@cd "%mapdata%"
python -V
@if ERRORLEVEL 1 goto failed


"%bspzipexe%" -addlist "%GameDir%\maps\%mapname%.bsp" "%GameDir%\maps\%mapname%.bsp.reslister" "%GameDir%\maps\%mapname%.bsp.new" 
@if ERRORLEVEL 1 goto failed
@cd /d "%CMD_LC_ROOT%"

@move "%GameDir%\maps\%mapname%.bsp.new" "%GameDir%\maps\%mapname%.bsp.newx"
@if ERRORLEVEL 1 goto failed
@del /Q /F "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed
move "%GameDir%\maps\%mapname%.bsp.newx" "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed


:missingcsstf

@if %NO_MISSING_BUNDLING%==1 goto missingcsstf_skip

@echo %NL% [33m# Packing potentially missing vmts to map (WARNING: BETA FEATURE)[0m

@rd /s /q "%GameDir%\data\mapoverrides" 2>nul
@del /Q /F "%GameDir%\data\addlist.txt" 2>nul
@del /Q /F "%GameDir%\data\addlist_src.txt" 2>nul

@cd /d "%CMD_LC_ROOT%"
@call extras\gmodcommander.cmd missing "%mapname%"
@if ERRORLEVEL 1 goto missingcsstf_fail
@if not exist "%GameDir%\data\addlist.txt" @goto missingcsstf_fail

@cd /d "%CMD_LC_ROOT%"

@echo Bspzipping the potentially missing

@cd "%GameDir%\data"
"%bspzipexe%" -addlist "%GameDir%\maps\%mapname%.bsp" "%GameDir%\data\addlist.txt" "%GameDir%\maps\%mapname%.bsp.new" 
@if ERRORLEVEL 1 goto failed

move "%GameDir%\maps\%mapname%.bsp.new" "%GameDir%\maps\%mapname%.bsp.newx"
@if ERRORLEVEL 1 goto failed
del /Q /F "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed
move "%GameDir%\maps\%mapname%.bsp.newx" "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed

@rd /S /Q "%GameDir%\data\mapoverrides"
@del /Q /F "%GameDir%\data\addlist.txt"
@del /Q /F "%GameDir%\data\addlist_src.txt"

@goto missingcsstf_finish
:missingcsstf_fail
@echo ">>>>>>> !!!FAILED!!! (non fatal). See %GameDir%\console.log"
:missingcsstf_skip
@echo Skipping...
:missingcsstf_finish



:extrabspzip
@echo ================= Packing extra data from list =================

@rem @echo Packing extra data from "%mapfolder%\%mapfile%.bspzip"... >> "%CMD_LC_ROOT%\bspzip_out.log"

@if not exist "%mapfolder%\%mapfile%.bspzip" @goto extrabspzip_skip

@cd "%mapdata%"
"%bspzipexe%" -addlist "%GameDir%\maps\%mapname%.bsp" "%mapfolder%\%mapfile%.bspzip" "%GameDir%\maps\%mapname%.bsp.new" 
@if ERRORLEVEL 1 goto failed
@rem >> "%CMD_LC_ROOT%\bspzip_out.log"

@rem 
@move "%GameDir%\maps\%mapname%.bsp.new" "%GameDir%\maps\%mapname%.bsp.newx"
@if ERRORLEVEL 1 goto failed
@del /Q /F "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed
move "%GameDir%\maps\%mapname%.bsp.newx" "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed
goto extrabspzip_ok
:extrabspzip_skip
echo Skipping packing. "%mapfile%.bspzip" not found.
:extrabspzip_ok


@if %NOLDR%==1 goto hdr

:ldr
@echo %NL% [33m# LDR Cubemaps[0m
@cd /d "%CMD_LC_ROOT%"
call extras\gmodcommander.cmd cubemaps_ldr "%mapname%"
@if ERRORLEVEL 1 goto ldrfail
@goto ldrok
:ldrfail
@echo WARNING: LDR builder CRASHED (ignoring). The map may still work.
:ldrok
@cd /d "%CMD_LC_ROOT%"

:hdr

@if %NOHDR%==1 goto hdrok

@echo %NL% [33m# HDR Cubemaps[0m
@cd /d "%CMD_LC_ROOT%"
@call extras\gmodcommander.cmd cubemaps_hdr "%mapname%"
@if ERRORLEVEL 1 goto hdrfail
@goto hdrok
:hdrfail
@echo WARNING: HDR builder CRASHED (ignoring). The map may still work.
:hdrok
@cd /d "%CMD_LC_ROOT%"





@if %ENABLE_BSPREZIP%==1 @goto hack_bsprezip
@goto hack_bsprezip_skip

:hack_bsprezip

@echo %NL% [33m# Repacking bsp due to bugs in bspzip[0m

COPY "%mapfolder%\%mapname%.bsp" "%GameDir%\maps\%mapname%_prezip.bsp"
@if ERRORLEVEL 1 goto failed

@cd /d "%CMD_LC_ROOT%"
call extras\gmodcommander.cmd bsprezip "%mapname%"
@if ERRORLEVEL 1 goto failed

@rem MOVE /Y "%GameDir%\maps\%mapname%.bsp" "%GameDir%\maps\%mapname%_broken.bsp"
@del /Q /F "%GameDir%\maps\%mapname%.bsp"
COPY "%GameDir%\data\%mapname%.bsp.dat" "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed


:bsprezip_ok
:hack_bsprezip_skip
@cd /d "%CMD_LC_ROOT%"




:navmesh
@echo ================= Generating navmesh =================

@set targetnav=%GameDir%\maps\%mapname%.nav

@if not exist "%mapfolder%\%mapfile%.lm.txt" @goto navmesh_noseeds

@cd /d "%CMD_LC_ROOT%"
copy /Y "%mapfolder%\%mapfile%.lm.txt" "%GameDir%"\data\navmesh_landmarks.txt
@if ERRORLEVEL 1 goto failed
@call extras\gmodcommander.cmd navmesh "%mapname%"
@if ERRORLEVEL 1 goto failed
@cd /d "%CMD_LC_ROOT%"

@goto navmesh_end
:navmesh_noseeds
@echo SKIPPING: Seed file missing "%mapfolder%\%mapfile%.lm.txt"
:navmesh_end

@rem Check navmesh existing and warn if not
@set size=0
@for /f %%i in ("%targetnav%") do set size=%%~zi
@if %size% gtr 0 @goto navok
@echo NAVMESH GENERATION FAILED (%targetnav%). Size=%size%
@goto navcskip
:navok
@rem @start "RUNBZIP2" /low /min extras\bzip2.exe -kf -9 "%GameDir%\maps\%mapname%.nav"
:navcskip

@echo ================= TESTING MAP (HDR) ================= 
@cd /d "%CMD_LC_ROOT%"
@extras\flashcmd.exe >nul 2>nul
if not %TESTBUILD%==1 call "LAUNCH game.cmd" -multirun -window -w 1280 -h 1024 +sv_noclipspeed 25 +mat_hdr_level 2 +mat_specular 1 +sv_cheats 1 -disableluarefresh -dev 2 +developer 2 +map %mapname%



@rem ============= GIT PUSH REQUEST ============

@if defined NOCOMPILERCOMMIT @GOTO gitpush_ending

@echo.
@echo [33mModified mapfiles:[0m
@git -C "%mapfolder%" status --untracked-files=no -s
@echo.


@git -C "%mapfolder%" diff-index --quiet HEAD
@if ERRORLEVEL 1 @GOTO gitpush_dirty

@echo [33m# All clean[0m
@GOTO gitpush_ending

:gitpush_dirty
@cd /d "%CMD_LC_ROOT%"
@extras\flashcmd.exe >nul 2>nul
@echo [33m# Uncommitted changes, launching command prompt for you.[0m

@echo.
@pushd .
@cd "%mapfolder%"

@bash.exe
@if ERRORLEVEL 1 @GOTO gitpush_bashfail
@GOTO gitpush_bashok
:gitpush_bashfail
cmd.exe

:gitpush_bashok
popd

:gitpush_ending







@goto win
























:failed
@echo COMPILE FAILURE!
@echo Press enter to continue (this will unlink testing addon)
@pause > nul
@goto gtfo





:win
@echo ====================
@echo ===== FINISHED =====
@echo ====================

@if %AUTO_UPLOAD_MAP%==1 goto uploader

@set /P DEC="Write y and press enter to run workshop publisher. Otherwise press enter to close. "
@if "%DEC%"=="y" @goto uploader 
@if "%DEC%"=="Y" @goto uploader
@goto gtfo


:uploader
@rmdir "%maptoolkit_temp_addon%" 2>nul
@cd /d "%CMD_LC_ROOT%"
@call publish_map.cmd
@goto gtfo

:gtfo
cd "%ORIGFOLDER%"
@rmdir "%maptoolkit_temp_addon%" 2>nul
@echo.