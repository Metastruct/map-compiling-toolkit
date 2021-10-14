@set ORIGFOLDER=%CD%
@set CMD_LC_ROOT=%~dp0
@set VBSPEXTRAS=-notjunc
@call common.cmd
@cd /d "%CMD_LC_ROOT%"

:docopy
@set targetvmf=%mapfolder%\ci.vmf
@set targetbsp=%mapfolder%\ci.bsp
@set leakfile=%mapfolder%\ci.lin
@del /Q /F "%targetvmf%" 2>nul >nul
@del /Q /F "%targetbsp%" 2>nul >nul

del /Q /F "%leakfile%"

@COPY "%mapfolder%\%mapfile%.vmf" "%targetvmf%" >nul
@if ERRORLEVEL 1 goto failed

extras\vmfii "%targetvmf%" "%targetvmf%" --fgd "%FGDS%"  > nul
@if ERRORLEVEL 1 goto failed
"%compilers_dir%\vbsp.exe" %VBSPEXTRAS% -allowdynamicpropsasstatic -leaktest -low "%targetvmf%"
@if ERRORLEVEL 1 goto failed
@if NOT exist "%targetbsp%" goto failed
@if exist "%leakfile%" goto failed
"%compilers_dir%\vvis.exe" -fast -low "%targetvmf%"
@if ERRORLEVEL 1 goto failed
"%compilers_dir%\vrad.exe" -low %VRADLDR% -noskyboxrecurse -bounce 1  -noextra  -fastambient  -fast -ldr "%targetvmf%"
@if ERRORLEVEL 1 goto failed
@goto ok

:failed
@exit 1
:ok
