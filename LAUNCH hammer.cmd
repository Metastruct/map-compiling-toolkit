@call config.bat
@regedit /S extras\hammer3d.reg
@cd /D "%sourcesdk%\bin"
@set SteamAppId=243750
@set SteamGameId=211
@set VProject=%VProject_Hammer%
@echo %VProject%
@pause > nul
@start /wait hammer.exe -debug -console -dev -nop4
