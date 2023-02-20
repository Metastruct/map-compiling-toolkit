@cd /d "%~dp0"
@call common.cmd

@set targetvbsp=%VProject_Hammer%\%mapfile%.vbsp
@COPY "%mapfolder%\%mapfile%.vbsp" "%targetvbsp%" 2>nul >nul

@call "LAUNCH hammer.cmd" "%mapfolder%\%mapfile%.vmf"
