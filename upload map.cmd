@call config.bat

@echo off
set HOST=g3.metastruct.org

echo Uploading version '%BUILD_VERSION%' target bz2: %GameDir%\maps\%mapname%.bsp.bz2

@if exist %GameDir%\maps\%mapname%.bsp.bz2 goto upload
@cd %GameDir%\maps\
@goto fail

:upload
cd %GameDir%\maps\
@echo Uploading
@echo on
scp -l python %mapname%.bsp.bz2 %HOST%:gserv/Maps/maps
scp -l python graphs/%mapname%.ain %HOST%:gserv/Maps/maps/graphs
@echo Decompressing on remote...
plink -l python %HOST% bunzip2 gserv/Maps/maps/%mapname%.bsp.bz2
@echo off
@goto win

:fail
@echo FILE %GameDir%\maps\%mapname%.bsp.bz2 MISSING!!?
@goto die
:win
@echo success
@goto die
:die
@pause > nul