
import os
import winreg
import subprocess
import vdf
from pathlib import Path
from functools import lru_cache
from pprint import pprint as PrintTable
# DETECT OS VERSION

def Is64Windows():
	return 'PROGRAMFILES(X86)' in os.environ

def GetProgramFiles32():
	if Is64Windows():
		return os.environ['PROGRAMFILES(X86)']
	else:
		return os.environ['PROGRAMFILES']

def GetProgramFiles64():
	if Is64Windows():
		return os.environ['PROGRAMW6432']
	else:
		return None

if Is64Windows() is True:
	key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, "SOFTWARE\\Wow6432Node\\Valve\\Steam")
else:
	key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, "SOFTWARE\\Valve\\Steam")
	
steampath =  winreg.QueryValueEx(key, "InstallPath")[0]
@lru_cache(maxsize=32)
def GetSteamPath():
	return steampath
	
@lru_cache(maxsize=32)
def GetSteamLibraryPaths():
	with open(GetSteamPath() + "/SteamApps/LibraryFolders.vdf") as lf:
		vdffile = vdf.parse(lf)
		vdflocations = [val for key,val in vdffile['LibraryFolders'].items() if key.isdigit()]+[steampath]
		for path in vdflocations:
			print("\tFound Library path: ",path)
		return vdflocations
		
@lru_cache(maxsize=32)
def GetGamePath(appid):
	for acfpath in GetSteamLibraryPaths():
		appmanifestpath = acfpath + "/SteamApps/appmanifest_%d.acf"%(appid)
		if os.path.isfile(appmanifestpath):
			appmanifest = vdf.parse(open(appmanifestpath))
			return Path(acfpath+"\\SteamApps\\common\\"+appmanifest['AppState']['installdir']+"\\")

@lru_cache(maxsize=32)
def GetGModPath():
	return GetGamePath(4000)

@lru_cache(maxsize=32)
def TF2Path(d="."):
	return GetGamePath(440) / d

@lru_cache(maxsize=32)
def CSSPath(d="."):
	return GetGamePath(240) / d

@lru_cache(maxsize=32)
def MapFiles(d="."):
	return Path("../../mapfiles").resolve() / d

@lru_cache(maxsize=32)
def MapAssets(d="."):
	return Path("../../mapdata").resolve() / d

@lru_cache(maxsize=32)
def HammerRoot():
	p = Path("../game_hammer").resolve()
	#assert p.exists()
	return p
	
@lru_cache(maxsize=32)
def CompilerRoot():
	p = Path("../game_compiling").resolve()
	#assert p.exists()
	return p
	
@lru_cache(maxsize=32)
def ToolkitRoot(d="."):
	return Path("..").resolve() / d




def execute_batch(cmd,cwd):
	p=subprocess.Popen(cmd,cwd=cwd)#, creationflags=subprocess.CREATE_NEW_CONSOLE)
	p.communicate()
	return p.returncode