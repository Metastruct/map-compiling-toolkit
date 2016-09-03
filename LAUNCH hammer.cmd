@cd /d "%~dp0"
@call config.bat

@echo Tweaking max draw distances...
@reg ADD "HKCU\Software\Valve\Hammer\3D Views" /v BackPlane /t REG_DWORD /d 20000 /f
@reg ADD "HKCU\Software\Valve\Hammer\3D Views" /v ModelDistance /t REG_DWORD /d 15000 /f
@reg ADD "HKCU\Software\Valve\Hammer\3D Views" /v DetailDistance /t REG_DWORD /d 5000 /f
@reg ADD "HKCU\Software\Valve\Hammer\2D Views" /v RotateConstrain /t REG_DWORD /d 1 /f
@reg ADD "HKCU\Software\Valve\Hammer\Splitter" /v "DrawType0,0" /t REG_DWORD /d 9 /f

@cd /D "%sourcesdk%\bin"
@set SteamAppId=243750
@set SteamGameId=211
@set VProject=%VProject_Hammer%

@echo Project: %VProject%

start hammer.exe %HammerParams% %*

@ping 127.0.0.1 -n 3 > nul
