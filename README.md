MS Map Compiling Toolkit
===================

Features
-------------

 - Map compiling (vbsp, vvis, vrad, vrad HDR). It's a batch file so configure to your liking yourself.
	 - Low priority, abort on error, etc
 - Instances support using VMFII
 - Auto map versioning (incremental numbering)
 - Automatic copying to game directory, etc
 - Autopack required custom content (and custom defined custom content)
 - Automatic cubemaps creation (LDR, HDR)
 - Workshop map uploading
 - Map testing before uploading
 - Launch hammer with expanded view range
 - bz2 packing
 - Experimental: Pack used CS:S/TF2 VMTs into BSP to be able to modify them if they are missing (less black and purple textures) 

Requirements
-------------
 - Steam
	 - Source SDK Base 2013 Multiplayer (we use the sdk hammer and compiling toolkit)
	 - Garry's Mod
	 - CS:S
	 - TF2
 - Metastruct SVN (or your own map data)
 - Java (for pakrat)
 - .NET (preinstalled most likely)
 - A lot of time


Example paths
-------------

These are some of the example paths to give idea where to put things on your computer

 - c:\Program Files (x86)\Steam\
 - c:\users\username\documents\metastruct_mapcompiler\user_config.cmd (this is what defines paths like where to get vbsp.exe)
 - c:\users\username\documents\metastruct_mapcompiler\game_hammer\gameinfo.txt (hammer reads this to mount things properly)
 - c:\users\username\documents\metastruct\mapdata\materials (mapdata = custom content)
 - c:\users\username\documents\metastruct\mapfiles\mymap.vmf (mapfiles = logs and vmfs mostly)


Setting up
-------------
*DISCLAIMER: Untested*

- Configure user_config.cmd! Example *user_config.cmd* in *user_config_example.cmd*
- **Copy** extras/gameinfo.txt
		-> mapcompiler\game_hammer\gameinfo.txt & mapcompiler\game_compiling\gameinfo.txt
 - Configure paths in the files.
- **Copy** extras/GameConfig.txt
		-> Folder that is opened by "GO sourcesdk_bin.cmd" (or append to the existing file if you know your way around)
      - Configure paths in the file (You only need to set the paths for "Garry's Mod MDK")
 
 
		**Extra**
		Copy extras/vbsp_patcher.exe to where vbsp.exe is and copy vbsp.exe to vbsp_patched.exe. Run and press patch.

Notes
-----
The map files are in read-only mode.
	This is to prevent unmergeable changes. To make it writeable again, lock it.
	After doing your changes, commit them and unlock the file again. 
	You can read more about this in the svn book, section "Locking" (you should already know this !!):
	http://svnbook.red-bean.com/en/1.5/svn-book.html#svn.advanced.locking

If you launch hammer using the shortcut and it asks for game to use, something is wrong.
	

Automatic uploading
-----
There is an uploader which can automate the uploading once you have managed to upload the initial version. Refer to http://wiki.garrysmod.com/page/Workshop_Publisher_Tool for additional syntax. Afraid there is no help for this part, but it's to make repeat uploading faster, not the initial uploading.

CS:S / TF2 Bundling 
-----
There exists a lua script which runs exclusively only in GMod, which can bundle the game VMTs into the map for missing material replacement purposes to reduce checkerboards. It doesn't know about vmt syntax yet so you shouldn't use it as it won't bundle everything missing. It also requires lua code, which has not been finished yet to make of any actual use. 

Does not work outside GMod. Does not support models bundling.
	
TF2 + CSS+GMod
-----
All three games mounted to hammer makes hammer's texture browser crash. All three games are needed for compiling, but not for hammer editor. Editing becomes tricky, but it can be overcome by removing tf2 hats and inventory from material list using tricks (ask @Python1320).

To make both compiling and hammer work:

game_compiling and game_hammer should have only the following difference to make things work:

game_compiling/gameinfo.txt:

		//game		".../Team Fortress 2/tf_misc"
		game		".../Team Fortress 2/tf/tf2_misc.vpk"

game_hammer/gameinfo.txt:

		game		".../Team Fortress 2/tf_misc"
		//game		".../Team Fortress 2/tf/tf2_misc.vpk"

tf2_misc is a folder where tf_misc has been extracted with GCFScape and from materials folder the "backpack" folder has been removed. Something else may need to be removed in the future.
