--- Install instructions ---
This build of Hammer++ only works when started inside a game/sourcemod based on the SDK 2013 Multiplayer engine (e.g. Counter Strike Source or Half Life 2 Deathmatch)

1. Find where the game/sourcemod is installed, I will use Source SDK 2013 Multiplayer as the example

2. Copy over everything inside this download's "bin" folder into SDK 2013's "bin" folder.
	Your paths should look like this:
	<steam install location>/steamapps/common/Source SDK Base 2013 Multiplayer/bin/hammerplusplus.exe
	<steam install location>/steamapps/common/Source SDK Base 2013 Multiplayer/bin/hammerplusplus/<other files>
	
3. Launch the Hammer++ exe, and you are done!

4. (Sourcemods only) the -game parameter is not required as it's automatically added
	This means you don't need to do the shortcut method anymore, simply start the hammerplusplus.exe
	
--- Other Information ---
Hammer++ does not use the GameConfig.txt, instead it uses its own GameConfig.txt located in the hammerplusplus sub folder. 
If not found, it copies the normal game configuration.
Keep this in mind when following any tutorials.

HLMV++ comes bundled with the download, it is optional and not required for Hammer++ to work.

--- Uninstallation ---
To uninstall, simply delete the hammerplusplus.exe
You can also optionally delete the hammerplusplus folder, but this will remove all saved settings for Hammer++.