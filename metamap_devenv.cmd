@prompt $G$S

git --version
IF ERRORLEVEL 1 GOTO fail

git clone https://github.com/Metastruct/map-compiling-toolkit.git
git clone git@gitlab.com:metastruct/mapdata.git mapdata
git clone https://github.com/Metastruct/meta-mapassets mapdata2
git clone git@gitlab.com:metastruct/mapfiles.git mapfiles

cd map-compiling-toolkit\setup
setup.exe


cd ..
"LAUNCH propperall.cmd"
notepad user_config.cmd

echo DEVENV AUTOSETUP FINISHED. You're on your own.
goto end
:fail 
echo FAILURE

:end
pause