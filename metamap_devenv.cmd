@prompt $G$S

@echo # Test if git exists
git --version
@IF ERRORLEVEL 1 GOTO fail

@echo # Test if gitlab is accessible
git ls-remote git@gitlab.com:metastruct/mapfiles.git
@IF ERRORLEVEL 1 GOTO fail


@echo # Clone all required repos
git clone https://github.com/Metastruct/map-compiling-toolkit.git map-compiling-toolkit
git clone git@gitlab.com:metastruct/mapdata.git mapdata
git clone https://github.com/Metastruct/meta-mapassets mapdata2
git clone git@gitlab.com:metastruct/mapfiles.git mapfiles

@echo # Autosetup folders and paths

cd map-compiling-toolkit\setup
setup.py
@IF ERRORLEVEL 1 GOTO setup_py_not_ok
@goto setup_py_ok

:setup_py_not_ok
setup.exe
@IF ERRORLEVEL 1 GOTO fail
:setup_py_ok

cd ..

@echo # run propper once to build models
"LAUNCH propperall.cmd"
@IF ERRORLEVEL 1 GOTO fail

notepad user_config.cmd

@echo DEVENV AUTOSETUP FINISHED. You're on your own.
@goto end
:fail 
@echo FAILURE

:end
@pause