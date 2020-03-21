@cd /d "%~dp0"
@call common.cmd

@if defined NOHAMMERAUTOUPDATE @GOTO updated

@echo.
@echo [33mModified mapfiles:[0m
@git -C "%mapfolder%" status --untracked-files=no -s
@echo.

@echo [33m# Autoupdating mapfiles...[0m

@git -C "%mapfolder%" pull
@if ERRORLEVEL 1 @GOTO updatefail

@echo.
@GOTO updated
:updatefail
@echo.

@echo [33m# AUTOUPDATE FAILED. Fix things here manually and type exit to continue.[0m
@pushd .
@cd "%mapfolder%"

@bash.exe
@if ERRORLEVEL 1 @GOTO bashfail
@GOTO bashok
:bashfail
@cmd.exe

:bashok
@popd

:updated


@if defined NOHAMMERTWEAKS @GOTO notweaking
@echo [33m# Autotweaking hammer settings...[0m

@reg ADD "HKCU\Software\Valve\Hammer\3D Views" /v BackPlane /t REG_DWORD /d 20000 /f > nul
@reg ADD "HKCU\Software\Valve\Hammer\3D Views" /v ModelDistance /t REG_DWORD /d 15000 /f > nul
@reg ADD "HKCU\Software\Valve\Hammer\3D Views" /v DetailDistance /t REG_DWORD /d 5000 /f > nul
@reg ADD "HKCU\Software\Valve\Hammer\2D Views" /v RotateConstrain /t REG_DWORD /d 1 /f > nul
@reg ADD "HKCU\Software\Valve\Hammer\Splitter" /v "DrawType0,0" /t REG_DWORD /d 9 /f > nul
:notweaking

@rem @set VProject=%VProject_Hammer%
@rem @echo Project: %VProject%

@TITLE "Hammer Repo Waiter"
@echo [33m# Waiting for hammer to close...[0m
@start /WAIT "Hammer" "%VProject_Hammer%\..\bin\hammer.exe" %HammerParams% %*

@if defined NOHAMMERAUTOUPDATE @GOTO ending

@echo.
@echo [33mModified mapfiles:[0m
@git -C "%mapfolder%" status --untracked-files=no -s
@echo.




@git -C "%mapfolder%" diff-index --quiet HEAD
@if ERRORLEVEL 1 @GOTO dirty

@echo [33m# All clean[0m
@GOTO clean

:dirty
@extras\flashcmd.exe >nul 2>nul
@echo [33m# Uncommitted changes, launching command prompt for you.[0m

@echo.
@pushd .
@cd "%mapfolder%"

@bash.exe
@if ERRORLEVEL 1 @GOTO bashfail2
@GOTO bashok2
:bashfail2
cmd.exe

:bashok2
popd

:clean



@ping 127.0.0.1 -n 10 > nul

:ending