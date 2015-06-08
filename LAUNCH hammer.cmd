@call config.bat
regedit /S hammer3d.reg
@cd /D "%sourcesdk%\bin"
@set SteamAppId=243750
@set SteamGameId=211
hammer.exe -debug -console -dev -nop4
