from utils import *
from pathlib import Path
import shutil
from shutil import copyfileobj
import vpk
import traceback
import sys

def my_except_hook(exctype, value, traceback):
	if exctype == KeyboardInterrupt:
		print("\n\n====== Something happened that we can't handle ======")
		print(exctype)
		print(value)
		print(traceback)
		input("\nThis may be a programming error.\n\nPress ENTER to close this window.")
		sys.exit(1)
	else:
		sys.__excepthook__(exctype, value, traceback)
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
pathcheck(False,"Hammer\t\t",HammerRoot())
pathcheck(False,"Compiler\t",CompilerRoot())
pathcheck(False,"TF2\t\t",TF2Path("tf"))
pathcheck(False,"CSS\t\t",CSSPath("cstrike"))
pathcheck(True,"Maps\t\t",MapFiles())
pathcheck(True,"Map assets\t",MapAssets())
print("")
	
def RebuildHammerRoot():
	if not (HammerRoot()/ 'garrysmod' / 'garrysmod_dir.vpk').exists():
		print("missing hammer copy, copying")
		(HammerRoot()/ 'garrysmod' / 'cfg').mkdir(parents=True, exist_ok=True)
		def mov(s,d):
			if (GetGModPath()/s).is_dir():
				shutil.copytree(str(GetGModPath()/s), str(HammerRoot()/ d))
			else:
				shutil.copy(str(GetGModPath()/s), str(HammerRoot()/ d))
			
		def link(s):
			os.link(str(GetGModPath()/s), str(HammerRoot()/ s))
		link("garrysmod/garrysmod_000.vpk")
		link("garrysmod/garrysmod_001.vpk")
		link("garrysmod/garrysmod_002.vpk")
		link("garrysmod/garrysmod_dir.vpk")
		mov("platform/platform_misc_000.vpk",'garrysmod/')
		mov("platform/platform_misc_dir.vpk",'garrysmod/')
		mov("garrysmod/steam.inf",'garrysmod/')
		with (HammerRoot() / 'garrysmod/steam_appid.txt').open('wb') as f:
			f.write(b"4000\n\0")
			
		mov("bin",'bin')
		
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
				shutil.copytree(str(GetGModPath()/s), str(CompilerRoot()/ d))
			else:
				shutil.copy(str(GetGModPath()/s), str(CompilerRoot()/ d))
			
		def link(s):
			os.link(str(GetGModPath()/s), str(CompilerRoot()/ s))
		link("garrysmod/garrysmod_000.vpk")
		link("garrysmod/garrysmod_001.vpk")
		link("garrysmod/garrysmod_002.vpk")
		link("garrysmod/garrysmod_dir.vpk")
		mov("platform/platform_misc_000.vpk",'garrysmod')
		mov("platform/platform_misc_dir.vpk",'garrysmod')
		mov("garrysmod/steam.inf",'garrysmod')
		mov("garrysmod/scripts",'garrysmod/scripts')
		
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
		return
	
	def GetAnyMap():
		for map in MapFiles().glob('*.vmf'):
			return map.replace(".vmf","")
		return "gm_mymap"

	with (Path('.') / 'user_config.cmd').open('r') as template, (ToolkitRoot() / 'user_config.cmd').open('w') as output:
		mapfile = (MapFiles() / 'metastruct_3.vmf').exists() and 'metastruct_3' or GetAnyMap()
		mapname = mapfile=="metastruct_3" and "gm_construct_m3" or "gm_mymap"
		
		output.write( template.read().format( SteamAppUser="ChangeMe",
			SteamPath=GetSteamPath(),
			SteamPathAlt=GetGamePath(4000).parents[0],
			mapfolder=MapFiles(),
			mapdata=MapAssets(),
			mapfile=mapfile,
			mapname=mapname
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

input("\nPress ENTER to close.")