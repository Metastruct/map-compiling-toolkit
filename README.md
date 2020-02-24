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
 - Map testing game launch before uploading
 - navmesh
 - Experimental: Pack used CS:S/TF2 VMTs into BSP to be able to modify them if they are missing (less black and purple textures with proper lua) 

Requirements
-------------
 - Steam
	 - Source SDK Base 2013 Multiplayer
	 - Garry's Mod
	 - CS:S
	 - TF2
 - Metastruct Map Datas (one repo for map files and one for map assets) (or your own map)
 - Python
 - (Git)[https://gitforwindows.org/] (Choose commit-as-is, add git to system PATH)
 - A lot of time

Setting up
-------------
- Download [metamap_devenv.cmd](https://raw.githubusercontent.com/Metastruct/map-compiling-toolkit/master/metamap_devenv.cmd)     
   - Place it on a path that has no spaces. It will download more folders to that folder.
   - Run it. Hope it finds everything automatically.
- Configure the opened user_config.cmd! (look inside common.cmd for configurable params)
- You're on your own now, maybe attempt launch hammer

Troubleshooting
-----

 - If hammer.cmd asks for a game to use, something is wrong.
   - If hammer does start, look at hammer's "console" to see if it failed to find for example the VPROJECT or TF2.

Automatic uploading
-----
There is a system to upload to workshop. After it is configured you can ideally just hit upload after compile test cycle and it should update the workshop addon. Help is still TODO.

You need addon.json and jpg and maybe other things.

CS:S / TF2 Bundling (TODO)
-----
CS:S and TF2 VMTs can be bundled into the map to allow players see devtexture instead of checkerboard. This needs lua too, though. This feature is enabled by default so you may want to disable it to save some space.
