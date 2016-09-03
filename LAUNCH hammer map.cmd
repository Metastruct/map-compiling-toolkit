@cd /d "%~dp0"
@call config.bat

@call "LAUNCH hammer.cmd" "%mapfolder%\%mapfile%.vmf"
