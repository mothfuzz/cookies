@echo off
echo compiling main...
odin build . -out:bin\cookies.exe

for %%a in ("examples\*.odin") do (
    echo compiling example: %%a
    odin build %%a -out:bin\%%~na.exe -file -o:speed
)

for /f "delims=" %%i in ('odin.exe root') do set "ODIN_ROOT=%%i"
cp %ODIN_ROOT%/vendor/sdl3/SDL3.dll bin/SDL3.dll
