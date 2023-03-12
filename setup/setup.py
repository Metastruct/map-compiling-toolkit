from utils import *
from pathlib import Path
import shutil
from shutil import copyfileobj
import vpk
import traceback
import sys,time
import distutils.dir_util

def has_debugger() -> bool:
    return hasattr(sys, 'gettrace') and sys.gettrace() is not None

GDIR='garrysmod'
USERCONFIG_TEMPLATE = r"""@rem see common.cmd for potential configuration options

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

def my_except_hook(*exc_info):
	if exc_info[0] == KeyboardInterrupt:
		input("\nABORTED.")
		sys.exit(1)
	else:
		print("\n\n====== Something unexpected happened that we can't handle ======")
		print("".join(traceback.format_exception(*exc_info)))
		input("This may be a programming error.\nCopy all of this screen and make an issue at https://github.com/Metastruct/map-compiling-toolkit/issues/new\n\nPress ENTER to abort.")
		sys.exit(1)
if not has_debugger():	
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
pathcheck(False,"CSGO\t\t",CSGOPath("csgo"))
pathcheck(True,"Maps\t\t",MapFiles())
pathcheck(True,"Map assets\t",MapAssets())
print("")

def link(s,target):
	try:
		os.link(    str(s), str(target))
	except OSError as e:
		shutil.copy(str(s), str(target))

def CreateMover(dest):
	def mov(s,d):
		if (s).is_dir():
			#print("copy_tree",s,dest/d)
			distutils.dir_util.copy_tree(str(s), str(dest / d))
		else:
			shutil.copy(str(s), str(dest/d))
	return mov

import errno,stat
def remove_error_handler(func, path, execinfo):
	e = execinfo[1]
	if e.errno == errno.ENOENT or not os.path.exists(path):
		return
	if func in (os.rmdir, os.remove) and e.errno == errno.EACCES:
		os.chmod(path, stat.S_IRWXU| stat.S_IRWXG| stat.S_IRWXO)
		func(path) 
	raise e

def RebuildHammerRoot():
	HAMMER= HammerRoot()
	mov = CreateMover(HAMMER)

	if not (HAMMER/ GDIR / 'garrysmod_dir.vpk').exists():
		print("missing hammer copy, copying")
		(HAMMER/ GDIR / 'cfg').mkdir(parents=True, exist_ok=True)

		mov(GetGModPath() / "garrysmod/steam.inf",'garrysmod/')
		mov(GetGModPath() / "garrysmod/detail.vbsp",'garrysmod/')
		with (HAMMER / 'garrysmod/steam_appid.txt').open('wb') as f:
			f.write(b"4000\n\0")
			
		mov(SDK2013MPPath() / "bin/",'bin/')
		mov(SDK2013MPPath() / "platform/",'platform/')
		#mov(GetGModPath() / "garrysmod/resource/",'garrysmod/resource/')
		hpp=HAMMER/'bin'/'hammerplusplus'
		print("hpp=",hpp)
		if hpp.is_dir():
			print("Deleting old hammerplusplus from copy...")
			for i in hpp.glob('*'):
				if not i.is_dir():
					i.unlink()

		# We don't want to mount hl2_misc_dir as game so we extract the shaders
		# ATTN: sourceengine/hl2_misc_dir.vpk shaders do not work with hammer++ 
		with vpk.open(str(SDK2013MPPath()/"hl2"/"hl2_misc_dir.vpk")) as hl2misc:
			for fpath in hl2misc:
				if fpath.startswith("shaders/"):
					(HAMMER / GDIR / Path(fpath).parents[0]).mkdir(parents=True, exist_ok=True)
					
					with hl2misc.get_file(fpath) as input,(HAMMER / GDIR / Path(fpath)).open('wb') as output:
						copyfileobj(input, output)

		#hpp.mkdir(exist_ok=False)
		#mov(ToolkitRoot() / "extras/slammin_2013mp/bin/",'bin/') # no work because limits :(
		mov(ToolkitRoot() / "extras/hammerplusplus_2013mp/bin/",'bin/')
					
def RebuildCompilerRoot():
	COMPILER = CompilerRoot()
	mov = CreateMover(COMPILER)
	if not (COMPILER/ GDIR / 'garrysmod_dir.vpk').exists():
		print("missing compiler root, copying")
		(COMPILER/ GDIR / 'cfg').mkdir(parents=True, exist_ok=True)

		link(GetGModPath() / "garrysmod/garrysmod_000.vpk",COMPILER/GDIR)
		link(GetGModPath() / "garrysmod/garrysmod_001.vpk",COMPILER/GDIR)
		link(GetGModPath() / "garrysmod/garrysmod_002.vpk",COMPILER/GDIR)
		link(GetGModPath() / "garrysmod/garrysmod_dir.vpk",COMPILER/GDIR)
		mov(GetGModPath()/"platform/platform_misc_000.vpk",GDIR)
		mov(GetGModPath()/"platform/platform_misc_dir.vpk",GDIR)
		mov(GetGModPath()/"garrysmod/steam.inf",GDIR)
		mov(GetGModPath()/"garrysmod/detail.vbsp",'garrysmod/')

		with (COMPILER / 'garrysmod/steam_appid.txt').open('wb') as f:
			f.write(b"4000\n\0")
		mov(GetGModPath() / "bin",'bin')
		#mov(CSGOPath() / "bin/",'bin/')
		#mov(CSGOPath() / "platform/",'platform/')
		#mov(ToolkitRoot() / "extras/metabsp/bin/",'bin/')


def BuildHammerGameConfig():
	with open(Path('.') / 'GameConfig.txt') as template:
		GameConfig = vdf.parse(template)

	conf=GameConfig["Configs"]["Games"]["GMODMAPDEV"]
	conf["GameDir"]=str(HammerRoot()/GDIR)
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
	
	# The game needs to be first for hammer++
	# moved to template
	#SearchPaths["game"]=HammerRoot()/GDIR
	SearchPaths["game"]=MapAssets()
	
	SearchPaths["game"]=TF2Path("tf")/"tf2_sound_misc.vpk"
	SearchPaths["game"]=TF2Path("tf")/"tf2_textures.vpk"
	SearchPaths["game"]=TF2Path("tf")/"tf2_misc.vpk"
	SearchPaths["game"]=CSSPath("cstrike")/"cstrike_pak.vpk"
	SearchPaths["game"]=GetGModPath()/"garrysmod/garrysmod.vpk"
	SearchPaths["game"]=GetGModPath()/"sourceengine/hl2_textures.vpk"
	SearchPaths["game"]=GetGModPath()/"sourceengine/hl2_sound_misc.vpk"
	SearchPaths["game"]=GetGModPath()/"sourceengine/hl2_misc.vpk"
	SearchPaths["game"]=GetGModPath()/"sourceengine"
	SearchPaths["platform"]=GetGModPath()/"sourceengine"
	SearchPaths["gamebin"]=GetGModPath()/"bin"
	SearchPaths["game+game_write"]=GetGModPath()/GDIR
	SearchPaths["game+download"]=GetGModPath()/'garrysmod/download'
	#SearchPaths["platform"]=GetGModPath()/"platform/platform_misc.vpk"
	
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
	
	
	
	with (ToolkitRoot() / 'user_config.cmd').open('w') as output:
		#TODO getenv?
		mapfile = (MapFiles() / 'metastruct_3.vmf').exists() and 'metastruct_3' or GetAnyMap()
		mapname = mapfile=="metastruct_3" and "gm_construct_m3" or "gm_mymap"
		
		output.write( USERCONFIG_TEMPLATE.format( SteamAppUser="ChangeMe",
			SteamPath=GetSteamPath(),
			SteamPathAlt=GetGModPath().parents[0],
			mapfolder=MapFiles(),
			mapdata=MapAssets(),
			mapfile=mapfile,
			mapname=mapname,
			GameDir=GetGModPath()/GDIR,
			GameExeDir=GetGModPath()
		))
	print("Generated user_config.cmd, edit it!")

def main():
	
	GenerateUserConfig()
	RebuildHammerRoot()
	write_mountcfg(HammerRoot() / 'garrysmod/cfg/mount.cfg')

	RebuildCompilerRoot()
	write_mountcfg(CompilerRoot() / 'garrysmod/cfg/mount.cfg')

	BuildHammerGameConfig()

	BuildGameInfo(HammerRoot() / 'garrysmod/gameinfo.txt')
	BuildGameInfo(CompilerRoot() / 'garrysmod/gameinfo.txt')

	input("\nPress ENTER to continue.")

main()