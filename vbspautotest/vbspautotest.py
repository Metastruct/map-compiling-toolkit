
import ctypes,sys,os
ctypes.windll.kernel32.SetConsoleTitleW("Hammer CI")

# UGH
def install_and_import(package,package_pip):
    import importlib
    try:
        importlib.import_module(package)
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', package_pip])
    finally:
        globals()[package] = importlib.import_module(package)


def callback_from_icon():
	pass

install_and_import("notify","winnotify")
import notify

ICO='install_icon_155236.ico'
notify.init(ICO, callback_from_icon)


from utils import *
from pathlib import Path
import shutil
from shutil import copyfileobj
import traceback
import distutils.dir_util
import time
import win32gui
import subprocess

import win32event
import win32api
from winerror import ERROR_ALREADY_EXISTS



mutex = win32event.CreateMutex(None, False, 'hammerciautotest')
last_error = win32api.GetLastError()

if last_error == ERROR_ALREADY_EXISTS:
   print("Already running")
   sys.exit(43)


def my_except_hook(*exc_info):
	if exc_info[0] == KeyboardInterrupt:
		sys.exit(0)
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

cifile = MapFiles("ci.vmf").resolve()
cilog  = MapFiles("ci.log").resolve()

watchables={vmf:1 or vmf.stat().st_size for vmf in MapFiles().glob("*.vmf") if vmf.resolve()!=cifile and "gm_construct_m" not in str(vmf)}

def watch():
	found=False
	for vmf,size in watchables.items():
		time.sleep(0)
		st_size=vmf.stat().st_size
		if st_size!=size:
			watchables[vmf]=st_size
			found=vmf
	if found:
		time.sleep(1)
		for vmf,size in watchables.items():
			time.sleep(0)
			st_size=vmf.stat().st_size
			if st_size!=size:
				watchables[vmf]=st_size
				found=vmf

	return found

def okcb(str):
	sys.stdout.write(str)
	sys.stdout.flush()

def failcb(str):
	sys.stderr.write(str)
	sys.stderr.flush()

wasfailed=False
firstcompile=True

def dofail(ret):
	
	
	if cilog.exists():
		print("Found log file")
		with cilog.open("rb") as f:
			f.seek(-512, os.SEEK_END)
			if b"LEAKED" in f.read():
				print("LEAK DETECT")
				notify.notify("Map leaked!",
							"Hammer CI",
							ICO,
							False,10,0x03)
				ctypes.windll.kernel32.SetConsoleTitleW("Status: MAP LEAKED")
				return
	notify.notify("Map compiling failed! Look at console window for more info. "+str(ret),"Hammer CI",
					
					
					ICO,
					False,10,0x03)
	ctypes.windll.kernel32.SetConsoleTitleW("Map compiling failed.")

startup_time = time.time()

check_fails=0
last_ret=None
def checkdead():
	global check_fails
	global last_ret
	if win32gui.FindWindow("VALVEWORLDCRAFT",None)!=0:
		return False
	check_fails += 1
	if check_fails < 5:
		return
	time.sleep(1)
	print("Shutting down")
	notify.notify("Shutting down. Last compile: "+(last_ret==None and "Unknown" or (last_ret==0 and '[SUCCESS]' or '[FAIL]')),"Hammer CI",
					
					
					ICO,
					False,10,last_ret==0 and 0x01 or 0x03)
	return True

while True:

	if checkdead():
		break

	changed = watch()
	if changed:
		print("\n\nRUNNING CI DUE TO FILE CHANGE: ",changed)
		cwd=os.getcwd()
		os.chdir(ToolkitRoot())
		
		start_time = time.time()

		ret = execute_batch(["test.cmd"],ToolkitRoot())
		
		e = int(time.time() - start_time)
		print('Compiling ran for {:02d}:{:02d}:{:02d}'.format(e // 3600, (e % 3600 // 60), e % 60))
		os.chdir(cwd)
		last_ret = ret
		ctypes.windll.kernel32.SetConsoleTitleW((ret==0 and '[SUCCESS]' or '[FAIL]') +'Compiling ran for {:02d}:{:02d}:{:02d}'.format(e // 3600, (e % 3600 // 60), e % 60))
		if ret == 0:
			if wasfailed or firstcompile:
				notify.notify("Compiling succeeded! :)\nTook {:02d}:{:02d}:{:02d}".format(e // 3600, (e % 3600 // 60), e % 60),"Hammer CI",
								
								ICO,
								False,10,0x01)
				firstcompile=False
			wasfailed=False
		else:
			wasfailed=True
			print("RETURN",ret)
			dofail(ret)
			time.sleep(10)
			print("Resuming monitoring...")
	time.sleep(1)
