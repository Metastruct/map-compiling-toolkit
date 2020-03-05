@rem ==== DONT MIND ME ====
@set NLM=^


@set NL=^^^%NLM%%NLM%^%NLM%%NLM%
@rem ======================

@echo %NL% [33m# Test if git exists[0m
git --version
@IF ERRORLEVEL 1 GOTO getgit
goto gitok
:getgit
@echo %NL% [33m# Install GIT! (choose add to path and commit as-is in setup)[0m
start "" https://gitforwindows.org/
@goto fail
:gitok

@echo %NL% [33m# Test if gitlab is accessible[0m
git ls-remote git@gitlab.com:metastruct/mapfiles.git
@IF ERRORLEVEL 1 GOTO try_gitlab_https
@GOTO gitlab_test_end

:try_gitlab_https
git ls-remote https://gitlab.com/metastruct/mapfiles.git
@IF ERRORLEVEL 1 GOTO fail
:gitlab_test_end

@echo %NL% [33m# Clone all required repos[0m


@if exist common.cmd (
    @echo %NL% [33m# NOTICE: Running in cloned repo mode[0m
	@pushd .
	@cd ..
) else (
    @echo %NL% [33m# NOTICE: Running in repoless mode[0m
	git clone https://github.com/Metastruct/map-compiling-toolkit.git map-compiling-toolkit --depth 5 --single-branch
	@IF ERRORLEVEL 1 GOTO fail
	@cd map-compiling-toolkit
	@pushd .
	@cd ..
)

git clone git@gitlab.com:metastruct/mapdata.git mapdata
@IF ERRORLEVEL 1 GOTO mapdata_fail
@goto mapdata_ok
:mapdata_fail
git clone https://gitlab.com/metastruct/mapdata.git mapdata
:mapdata_ok

git clone https://github.com/Metastruct/meta-mapassets mapdata2

git clone git@gitlab.com:metastruct/mapfiles.git mapfiles
@IF ERRORLEVEL 1 GOTO mapfiles_fail
@goto mapfiles_ok
:mapfiles_fail
git clone https://gitlab.com/metastruct/mapfiles.git mapfiles
:mapfiles_ok


@echo %NL% [33m# Autosetup folders and paths[0m

@popd
@pushd .
cd setup
@echo %NL% [33m# Attempting python based installation (this might fail)[0m
pip install -r requirements.txt
python setup.py
@IF ERRORLEVEL 1 GOTO setup_py_not_ok
@goto setup_py_ok

:setup_py_not_ok
@echo %NL% [33m# Running setup executable[0m
setup.exe
@IF ERRORLEVEL 1 GOTO fail
:setup_py_ok

cd ..

@echo %NL% [33m# run propper once to build models[0m
CALL "LAUNCH propperall.cmd"
@IF ERRORLEVEL 1 GOTO fail

notepad user_config.cmd

@echo %NL% [33m DEVENV AUTOSETUP FINISHED. Attempting loading map.[0m
CALL "LAUNCH hammer map.cmd"
@goto end
:fail 
@echo %NL% [33m FAILURE[0m

:end
@echo.
@pause