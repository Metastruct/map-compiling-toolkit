Setting up:
	INSTALL: Steam, Source SDK Base 2013 Multiplayer, GarrysMod, CS:S, TF2, but NOT SourceSDK
	NEED: Metastruct SVN in a static location
	
	CHECK: Your REAL garrysmod should locate in steamapps/common/GarrysMod/garrysmod
		If GMod is still located in steamapps/$steam_username$/GarrysMod/garrysmod, close steam, go in steamapps/$steam_username$/, cut the GMod folder
		and paste it in steamapps/common/. Go back in your steamapps folder, open appmanifest_4000.acf with Notepad and update the "installdir" and
		"appinstalldir" fields.
	
	PAY ATTENTION: 
		After this you will have two GMod installations, one of which is only used to make hammer use a clean installation and mount TF2 and CS:S properly
		Do not mix the config paths with each other. The example paths should provide enough information.
	
	Configure metastruct_tools/config.bat for your needs (fixing all absolute paths)
		AFTER: Run it once to see if it complains of anything

	Copy (and replace)
		extras/vbsp_patched.exe:
		extras/GameConfig.txt:
			-> Folder that is opened by "GO sourcesdk_bin.cmd" (or append to the existing file if you know your way around)

		steamapps/common/GarrysMod/garrysmod: (do not copy addons, download* folders and such)
			-> steam\steamapps\sourcemods\garrysmod_mapcompile
			SO THAT: you have (for example) steamapps\sourcemods\garrysmod_mapcompile\garrysmod_002.vpk

		extras/gameinfo.txt:
			-> steam\steamapps\sourcemods\garrysmod_mapcompile\gameinfo.txt

	Configure the copied GameConfig.txt to match the paths you have yourself
		You only need to configure "Garry's Mod MDK" in the bottom

	Configure the copied gameinfo.txt to match the paths you have yourself
		(Find and fix every path that starts with "X:/")
		
	The map file (metastruct_2.vmf) is in read-only mode.
		This is to prevent unmergeable changes. To make it writeable again, lock it.
		After doing your changes, commit them and unlock the file again. Please make sure to not forget unlocking it!
		You can read more about this in the svn book, section "Locking" (you should already know this !!):
		http://svnbook.red-bean.com/en/1.5/svn-book.html#svn.advanced.locking

	
Compiling:  

	Test that pakrat.jar can be launched (otherwise automation breaks)
	
	If VBSP Crashes:
		CHECK: vbsp_patched.exe should be the same size of vbsp.exe on the folder. 
		IF NOT: Delete vbsp_patched.exe, copy vbsp.exe -> vbsp_patched.exe, launch extras/vbsp patcher.exe and patch the copied file. Try compiling again.
		
	LAUNCH compile.cmd
		It does
		- Copying/renaming vmf for proper compiling
		- Instances collapsing
		- VBSP
		- VVIS
		- VRAD
		- Cubemap Erase (needs to be done due to bug in SDK)
		- Custom Files Packing
		- File Copying to your REAL GarrysMod
		- Game Launch for cubemap building and testing
			- How to build cubemaps (LDR+HDR are required)
				- mat_hdr_level 0
				- mat_specular 0
				- OPEN MAP
				- buildcubemaps
				- disconnect
				- mat_hdr_level 2
				- open map
				- buildcubemaps
				- mat_reloadallmaterials
				- mat_specular 1
				- Enjoy working map!
		- bzip2 Packing for shipping

		WARNING: Never ever rename the map even if it has wrong version, you have to recompile!
		
Uploading:
	TODO
