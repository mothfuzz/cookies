@echo off
echo compiling main...
odin build src\lib -out:bin\cookies.dll -collection:cookies=src -build-mode:dll

for /f "delims=" %%i in ('odin.exe root') do set "ODIN_ROOT=%%i"
cp %ODIN_ROOT%/vendor/sdl3/SDL3.dll bin/SDL3.dll
