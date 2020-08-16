@echo off
setlocal
:PROMPT
SET /P AREYOUSURE=Are you sure (Y/[N])?
IF /I "%AREYOUSURE%" NEQ "Y" GOTO END

echo Batch to delete minidumps

del "%CD%\*.mdmp" /s /f /q

echo Done!


:END
endlocal