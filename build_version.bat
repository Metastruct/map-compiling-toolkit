@SET /p old_version=<"%version_file%"

@set ADDSUB=%1

@if "%ADDSUB%"=="" goto setnop
@goto contin
:setnop
@set ADDSUB=0
:contin

@SET /a BUILD_VERSION=%old_version%+(%ADDSUB%)
@ATTRIB -R -H "%version_file%"
@echo %BUILD_VERSION% >"%version_file%"
@ATTRIB +R +H "%version_file%"
