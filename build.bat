@echo off
echo compiling main...
odin build . -out:bin\cookies.exe

for %%a in ("examples\*.odin") do (
    echo compiling example: %%a
    odin build %%a -out:bin\%%~na.exe -file
)
