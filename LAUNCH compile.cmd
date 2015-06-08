@set VRADHDR=-softsun 2 -final
@set VRADLDR=%VRADHDR%
@set TESTBUILD=0
@set AUTO_UPLOAD_MAP=0

@rem Store current folder
@set CMD_LC_ROOT=%~dp0

@cd /d "%CMD_LC_ROOT%"
@call config.bat
@cd /d "%CMD_LC_ROOT%"
@title Map Batch Compiler







@call build_version.bat 1
@cd /d "%CMD_LC_ROOT%"
@call config.bat
@cd /d "%CMD_LC_ROOT%"
@echo Version to build: %BUILD_VERSION%
@echo In: %mapfile%.vmf
@echo Out: %mapname%.bsp
@call build_version.bat -1
@cd /d "%CMD_LC_ROOT%"
@call config.bat
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
@call build_version.bat 1
@cd /d "%CMD_LC_ROOT%"
@call config.bat
@cd /d "%CMD_LC_ROOT%"


@goto dobuild

:buildprev
@call build_version.bat
@cd /d "%CMD_LC_ROOT%"
@echo Rebuilding version %BUILD_VERSION%.
@goto dobuild

:dobuild












@echo Compiling version '%BUILD_VERSION%' target bsp: "%mapfolder%\%mapname%.bsp"



:docopy
@set targetvmf=%mapfolder%\%mapname%.vmf
COPY "%mapfolder%\%mapfile%.vmf" "%targetvmf%"
@if ERRORLEVEL 1 goto failed








:vmfii
@echo ================= VMF Merging =================
vmfii "%targetvmf%" "%targetvmf%" --fgd "%FGDS%"
@if ERRORLEVEL 1 goto failed











:vbsp
@echo ================= VBSP ====================================================

@set VBSPNAME=vbsp_patched.exe
@%VBSPNAME% >nul 2>nul
@if ERRORLEVEL 9009 goto nopatched
@goto patched
:nopatched
@echo WARNING: vbsp_patched.exe could not be found
@set VBSPNAME=vbsp.exe
:patched

%VBSPNAME% -leaktest -low "%mapfolder%\%mapname%"
@if ERRORLEVEL 1 goto failed




:vvis
@echo ================= VVIS ====================================================

if not %TESTBUILD%==1 vvis.exe -low "%mapfolder%\%mapname%"
@if ERRORLEVEL 1 goto failed


:vrad
:vradldr
@echo ================= VRAD LDR ================================================
if not %TESTBUILD%==1 vrad.exe -low %VRADLDR% -softsun 2 -ldr "%mapfolder%\%mapname%"
@if ERRORLEVEL 1 goto failed


:vradhdr
@echo ================= VRAD HDR ================================================
if not %TESTBUILD%==1 vrad.exe -low %VRADHDR% -noskyboxrecurse -hdr "%mapfolder%\%mapname%"
@if ERRORLEVEL 1 goto failed











:reprocess

:copy
@echo ================= Copying to game =========================================
COPY "%mapfolder%\%mapname%.bsp" "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed

:cubemap
@echo ================= Deleting default cubemaps ===============================
bspzip -deletecubemaps "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed

:pack
@echo ================= Packing required files to map ===========================
pakrat.jar -auto "%mapdata%" "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed

:missingcsstf

@if %NO_MISSING_BUNDLING%==1 goto missingcsstf_skip

@echo ================= Packing potentially missing vmts to map (WARNING: BETA FEATURE) =================

@rd /s /q "%GameDir%\data\mapoverrides" 2>nul
@del /Q /F "%GameDir%\data\addlist.txt" 2>nul
@del /Q /F "%GameDir%\data\addlist_src.txt" 2>nul

@cd /d "%CMD_LC_ROOT%"
@call extras\gmodcommander.cmd missing "%mapname%"
@if ERRORLEVEL 1 goto failed
@cd /d "%CMD_LC_ROOT%"


@cd "%GameDir%\data"
bspzip -addlist "%GameDir%\maps\%mapname%.bsp" "%GameDir%\data\addlist.txt" "%GameDir%\maps\%mapname%.bsp.new" >> "%CMD_LC_ROOT%\bspzip_out.log"
@if ERRORLEVEL 1 goto failed

@move "%GameDir%\maps\%mapname%.bsp.new" "%GameDir%\maps\%mapname%.bsp.newx"
@if ERRORLEVEL 1 goto failed
@del /Q /F "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed
move "%GameDir%\maps\%mapname%.bsp.newx" "%GameDir%\maps\%mapname%.bsp"
@if ERRORLEVEL 1 goto failed

@rd /S /Q "%GameDir%\data\mapoverrides"
@del /Q /F "%GameDir%\data\addlist.txt"
@del /Q /F "%GameDir%\data\addlist_src.txt"

@goto missingcsstf_finish
:missingcsstf_skip
echo Skipping...
:missingcsstf_finish

:extrabspzip
@echo ================= Packing extra data from list =================

@rem @echo Packing extra data from "%mapfolder%\%mapfile%.bspzip"... >> "%CMD_LC_ROOT%\bspzip_out.log"

@if not exist "%mapfolder%\%mapfile%.bspzip" @goto extrabspzip_skip

@cd "%mapdata%"
bspzip -addlist "%GameDir%\maps\%mapname%.bsp" "%mapfolder%\%mapfile%.bspzip" "%GameDir%\maps\%mapname%.bsp.new" 
@rem >> "%CMD_LC_ROOT%\bspzip_out.log"
@if ERRORLEVEL 1 goto failed

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


:ldr
@echo ================= Generating LDR Cubemaps =================
@cd /d "%CMD_LC_ROOT%"
call extras\gmodcommander.cmd cubemaps_ldr "%mapname%"
@if ERRORLEVEL 1 goto failed
@cd /d "%CMD_LC_ROOT%"

:hdr
@echo ================= Generating HDR Cubemaps =================
@cd /d "%CMD_LC_ROOT%"
@call extras\gmodcommander.cmd cubemaps_hdr "%mapname%"
@if ERRORLEVEL 1 goto failed
@cd /d "%CMD_LC_ROOT%"


@echo ================= bzip2 Packing ================= 
start /low /min bzip2 -kf -9 "%GameDir%\maps\%mapname%.bsp"
start /low /min bzip2 -kf -9 "%GameDir%\maps\graphs\%mapname%.ain"

@echo ================= TESTING MAP (LDR) ================= 

if not %TESTBUILD%==1 call "LAUNCH game.cmd" -multirun -window -w 1024 -h 768 +sv_noclipspeed 25 +mat_hdr_level 0 +mat_specular 1 +sv_cheats 1 -disableluarefresh -dev 2 +developer 2 +map %mapname%
bzip2 -kf -9 "%GameDir%\maps\%mapname%.nav"


@goto win
























:failed
@echo COMPILE FAILURE!

@pause > nul
@goto gtfo





:win
@echo =======================
@echo ====== FINISHED =======
@echo =======================

@if %AUTO_UPLOAD_MAP%==1 goto uploader

@set /P DEC="Write y and press enter to run workshop publisher. Otherwise press enter to close "
@if "%DEC%"=="y" @goto uploader 
@goto gtfo


:uploader
@cd /d "%CMD_LC_ROOT%"
@call publish_map.cmd
@goto gtfo

:gtfo
@echo.