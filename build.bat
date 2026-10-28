@echo off
rem Builds the pastel command-line tool into bin\pastel.exe (Windows).
cd /d "%~dp0"
if not exist bin mkdir bin
if not exist build\cli mkdir build\cli
fpc -Mobjfpc -Sh -O2 -Xs -XX -vewn -FUbuild\cli -Fucli\src -FEbin -opastel.exe cli\pastel.pas
if errorlevel 1 exit /b 1
echo Built bin\pastel.exe
