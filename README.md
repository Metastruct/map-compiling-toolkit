MS Map Compiling Toolkit
===================

A self-contained map editing and compiling environment in a folder.

Features
-------------

 - Map compiling (vbsp, vvis, vrad, vrad HDR). It's a Python script (maptoolkit.cmd), configure via config.toml.
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
	 - [Garry's Mod](steam://install/4000) (x86-64 branch)
	 - [CS:S](steam://install/240)
	 - [TF2](steam://install/440)
 - Metastruct Map Datas (one repo for map files and one for map assets) (or your own map)
 - **NO LONGER NEEDED** [Python3](https://www.python.org/downloads/) (Choose add python.exe to path during installation)
 - [Git](https://gitforwindows.org/) (Choose commit-as-is and choose add git.exe to system PATH during installation)
 - A lot of time

Setting up for metastruct map
-------------
1. Place the toolkit in an empty folder that has no spaces in the folder path, with 5GB free disk space.
2. Run `setup\setup.exe` (or `setup\setup.py`) to copy the required game binaries into `game_hammer` and `game_compiling`.
3. Configure `config.toml`! (look inside config.toml for configurable params)
4. DONE! Launch tasks via `maptoolkit.cmd` (run `maptoolkit.cmd status` for the task list).
5. **If everything goes wrong** delete the folder and redo everything with fixes

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
