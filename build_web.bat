@echo off
echo compiling main...
odin build . -out:bin\cookies.wasm -target:js_wasm32

for %%a in ("examples\*.odin") do (
    echo compiling example: %%a
    odin build %%a -out:bin\%%~na.wasm -file -target:js_wasm32
)

cp engine/audio/audio.js bin/audio.js

echo start a web server in bin to run it!!
