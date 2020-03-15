from utils import *
from pathlib import Path
import shutil
from shutil import copyfileobj
import vpk
import traceback
import sys
import distutils.dir_util

def my_except_hook(*exc_info):
	if exc_info[0] == KeyboardInterrupt:
		input("\nABORTED.")
		sys.exit(1)
	else:
		print("\n\n====== Something unexpected happened that we can't handle ======")
		print("".join(traceback.format_exception(*exc_info)))
		input("This may be a programming error.\nCopy all of this screen and make an issue at https://github.com/Metastruct/map-compiling-toolkit/issues/new\n\nPress ENTER to abort.")
		sys.exit(1)
		
sys.excepthook = my_except_hook

def pathcheck(fatal,printthing,path):
	if path.exists():
		print("\t",printthing,path)
	else:
		print("\t",printthing,path," !!!! MISSING !!!!")
		if fatal:
			input("\nPress ENTER to abort.")
			sys.exit(1)

print("\nChecking paths:")
pathcheck(True,"GMod\t\t",GetGModPath())
if not (GetGModPath() / 'bin/win64').exists():
	input("\nERROR: You need to run GMod in x86-64 branch for devenv to work.\n\nPress ENTER to abort.")
	sys.exit(1)

pathcheck(False,"Hammer\t\t",HammerRoot())
pathcheck(False,"Compiler\t",CompilerRoot())
pathcheck(False,"TF2\t\t",TF2Path("tf"))
pathcheck(False,"CSS\t\t",CSSPath("cstrike"))
pathcheck(True,"Maps\t\t",MapFiles())
pathcheck(True,"Map assets\t",MapAssets())
print("")

def link_files(s,target):
	try:
		os.link(    str(GetGModPath()/s), str(target/ s))
	except OSError as e:
		shutil.copy(str(GetGModPath()/s), str(target/ s))
		
				
def RebuildHammerRoot():
	if not (HammerRoot()/ 'garrysmod' / 'garrysmod_dir.vpk').exists():
		print("missing hammer copy, copying")
		(HammerRoot()/ 'garrysmod' / 'cfg').mkdir(parents=True, exist_ok=True)
		def mov(s,d):
			if (GetGModPath()/s).is_dir():
				distutils.dir_util.copy_tree(str(GetGModPath()/s), str(HammerRoot()/ d))
			else:
				shutil.copy(str(GetGModPath()/s), str(HammerRoot()/ d))
			
		link_files("garrysmod/garrysmod_000.vpk",HammerRoot())
		link_files("garrysmod/garrysmod_001.vpk",HammerRoot())
		link_files("garrysmod/garrysmod_002.vpk",HammerRoot())
		link_files("garrysmod/garrysmod_dir.vpk",HammerRoot())
		mov("platform/platform_misc_000.vpk",'garrysmod/')
		mov("platform/platform_misc_dir.vpk",'garrysmod/')
		mov("garrysmod/steam.inf",'garrysmod/')
		with (HammerRoot() / 'garrysmod/steam_appid.txt').open('wb') as f:
			f.write(b"4000\n\0")
			
		mov("bin/",'bin/')
		mov("platform/",'platform/')
		mov("garrysmod/resource/",'garrysmod/resource/')
		
		# hammer needs shaders
		with vpk.open(str(GetGModPath()/"sourceengine/hl2_misc_dir.vpk")) as hl2misc:
			for fpath in hl2misc:
				if fpath.startswith("shaders/"):
					(HammerRoot() / 'garrysmod' / Path(fpath).parents[0]).mkdir(parents=True, exist_ok=True)
					
					with hl2misc.get_file(fpath) as input,(HammerRoot() / 'garrysmod' / Path(fpath)).open('wb') as output:
						copyfileobj(input, output)
					
def RebuildCompilerRoot():
	if not (CompilerRoot()/ 'garrysmod' / 'garrysmod_dir.vpk').exists():
		print("missing compiler root, copying")
		(CompilerRoot()/ 'garrysmod' / 'cfg').mkdir(parents=True, exist_ok=True)
		def mov(s,d):
			if (GetGModPath()/s).is_dir():
				distutils.dir_util.copy_tree(str(GetGModPath()/s), str(CompilerRoot()/ d))
			else:
				shutil.copy(str(GetGModPath()/s), str(CompilerRoot()/ d))
			

		link_files("garrysmod/garrysmod_000.vpk",CompilerRoot())
		link_files("garrysmod/garrysmod_001.vpk",CompilerRoot())
		link_files("garrysmod/garrysmod_002.vpk",CompilerRoot())
		link_files("garrysmod/garrysmod_dir.vpk",CompilerRoot())
		mov("platform/platform_misc_000.vpk",'garrysmod')
		mov("platform/platform_misc_dir.vpk",'garrysmod')
		mov("garrysmod/steam.inf",'garrysmod')

		
		with (CompilerRoot() / 'garrysmod/steam_appid.txt').open('wb') as f:
			f.write(b"4000\n\0")
		mov("bin",'bin')


def BuildHammerGameConfig():
	with open(Path('.') / 'GameConfig.txt') as template:
		GameConfig = vdf.parse(template)

	conf=GameConfig["Configs"]["Games"]["GMODMAPDEV"]
	conf["GameDir"]=str(HammerRoot()/'garrysmod')
	Hammer=conf["Hammer"]
	Hammer["BSP"] = str(CompilerRoot()/'bin/win64/vbsp.exe')
	Hammer["Vis"] = str(CompilerRoot()/'bin/win64/vvis.exe')
	Hammer["Light"] = str(CompilerRoot()/'bin/win64/vrad.exe')
	Hammer["GameData0"] = str(HammerRoot()/'bin/halflife2.fgd')
	Hammer["GameData1"] = str(ToolkitRoot()/'extras/propper/bin/propper.fgd')
	Hammer["GameData2"] = str(MapFiles()/'metastruct.fgd')
	Hammer["GameExeDir"]= str(GetGModPath())
	Hammer["MapDir"]= str(GetGModPath()/'garrysmod/maps')
	Hammer["GameExe"]= str(GetGModPath()/'hl2.exe')
	Hammer["BSPDir"]=Hammer["MapDir"]
	
	target=HammerRoot() / 'bin/GameConfig.txt'
	with target.open('w') as out:
		vdf.dump(GameConfig, out, pretty=True)
	print("Generated ",target,"!")
	
def write_mountcfg(target):
	with open(Path('.') / 'mount.cfg') as template:
		mountcfg = vdf.parse(template)

	conf=mountcfg["mountcfg"]
	conf["cstrike"]=CSSPath("cstrike")
	conf["tf"]=TF2Path("tf")
	conf["mapdata"]=MapAssets()
	conf["sourceengine"]=GetGModPath()/'sourceengine'
	
	with target.open('w') as out:
		vdf.dump(mountcfg, out, pretty=True)
	print("Generated ",target,"!")

def BuildGameInfo(target):
	with open(Path('.') / 'gameinfo.txt') as template:
		gameinfo = vdf.parse(template,mapper=vdf.VDFDict)

	conf=gameinfo["GameInfo"]

	conf["GameData"] = HammerRoot()/'bin/base.fgd'
	conf["GameData0"] = HammerRoot()/'bin/halflife2.fgd'
	conf["GameData1"] = MapFiles()/'metastruct.fgd'
	
	conf["InstancePath"]=MapAssets()
	conf["sourceengine"]=GetGModPath()/'sourceengine'
	
	SearchPaths=conf["FileSystem"]["SearchPaths"]
	SearchPaths["game"]=MapAssets()
	
	SearchPaths["game"]=TF2Path("tf")/"tf2_sound_misc.vpk"
	SearchPaths["game"]=TF2Path("tf")/"tf2_textures.vpk"
	SearchPaths["game"]=TF2Path("tf")/"tf2_misc.vpk"
	SearchPaths["game"]=CSSPath("cstrike")/"cstrike_pak.vpk"
	SearchPaths["game"]=GetGModPath()/"garrysmod/garrysmod.vpk"
	SearchPaths["game"]=GetGModPath()/"sourceengine/hl2_textures.vpk"
	SearchPaths["game"]=GetGModPath()/"sourceengine/hl2_sound_misc.vpk"
	SearchPaths["game"]=GetGModPath()/"sourceengine/hl2_misc.vpk"
	SearchPaths["gamebin"]=GetGModPath()/"bin"
	SearchPaths["game+game_write"]=GetGModPath()/'garrysmod'
	SearchPaths["game+download"]=GetGModPath()/'garrysmod/download'
	SearchPaths["platform"]=GetGModPath()/"platform/platform_misc.vpk"
	
	with target.open('w') as out:
		vdf.dump(gameinfo, out, pretty=True)
	print("Generated ",target,"!")

def GenerateUserConfig():
	if (ToolkitRoot() / 'user_config.cmd').exists():
		print("NOTICE: user_config.cmd already exists. If you need to regenerate it, remove it first.")
		return
	
	def GetAnyMap():
		for map in MapFiles().glob('*.vmf'):
			return map.replace(".vmf","")
		return "gm_mymap"
	
	template=r"""@rem see common.cmd for potential configuration options

@set SteamAppUser={SteamAppUser}
@set SteamPath={SteamPath}

@set SteamPathAlt={SteamPathAlt}

@set mapfolder={mapfolder}
@set version_file=%mapfolder%\ver_meta3.txt
@set mapdata={mapdata}
@set GameDir={GameDir}
@set GameExeDir={GameExeDir}

@set mapwsid=123456
@set mapfile={mapfile}
@set mapname={mapname}_%BUILD_VERSION%

"""
	
	with (ToolkitRoot() / 'user_config.cmd').open('w') as output:
		mapfile = (MapFiles() / 'metastruct_3.vmf').exists() and 'metastruct_3' or GetAnyMap()
		mapname = mapfile=="metastruct_3" and "gm_construct_m3" or "gm_mymap"
		
		output.write( template.format( SteamAppUser="ChangeMe",
			SteamPath=GetSteamPath(),
			SteamPathAlt=GetGModPath().parents[0],
			mapfolder=MapFiles(),
			mapdata=MapAssets(),
			mapfile=mapfile,
			mapname=mapname,
			GameDir=GetGModPath()/'garrysmod',
			GameExeDir=GetGModPath()
		))
	print("Generated user_config.cmd, edit it!")
GenerateUserConfig()
RebuildHammerRoot()
write_mountcfg(HammerRoot() / 'garrysmod/cfg/mount.cfg')

RebuildCompilerRoot()
write_mountcfg(CompilerRoot() / 'garrysmod/cfg/mount.cfg')

BuildHammerGameConfig()

BuildGameInfo(HammerRoot() / 'garrysmod/gameinfo.txt')
BuildGameInfo(CompilerRoot() / 'garrysmod/gameinfo.txt')

input("\nPress ENTER to continue.")
