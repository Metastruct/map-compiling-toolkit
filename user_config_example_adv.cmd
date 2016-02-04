@rem see config.cfg for potential configuration paths

@set SteamAppUser=Python132o
@set SteamPath=x:\g\steam

@set SteamPathAlt=x:\g\steamlib

@set mapfolder=X:\do\gmod\metastruct\mapfiles

@set mapdata=X:\do\gmod\metastruct\mapdata

:metaver
@if "%METAVER%"=="2" @GOTO META2
@if "%METAVER%"=="3" @GOTO META3
@set /P METAVER="Meta 2 or 3> "
@goto metaver

:META3
@set mapfile=metastruct_3
@set mapname=gm_construct_m3_%BUILD_VERSION%
@set mapwsid=481548423
@set version_file=%mapfolder%\ver.txt
@GOTO METAVER_END
:META2
@set mapfile=metastruct_2
@set mapname=gm_construct_m_%BUILD_VERSION%
@set mapwsid=426381305
@set version_file=%mapfolder%\ver_meta2.txt
@GOTO METAVER_END
:METAVER_END

@set GameExeDir=%SteamPathAlt%\steamapps\common\GarrysMod
@set GameDir=%GameExeDir%\garrysmod
