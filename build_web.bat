@echo off

set INITIAL_MEMORY_PAGES=2000
set MAX_MEMORY_PAGES=65536
set PAGE_SIZE=65536
set /a INITIAL_MEMORY_BYTES=%INITIAL_MEMORY_PAGES% * %PAGE_SIZE%
set /a MAX_MEMORY_BYTES=%MAX_MEMORY_PAGES% * %PAGE_SIZE%

echo compiling main...
odin build . -out:bin\cookies.wasm -target:js_wasm32 -extra-linker-flags:"--export-table --import-memory --initial-memory=%INITIAL_MEMORY_BYTES% --max-memory=%MAX_MEMORY_BYTES%"

for %%a in ("examples\*.odin") do (
    echo compiling example: %%a
    odin build %%a -out:bin\%%~na.wasm -file -target:js_wasm32 -extra-linker-flags:"--export-table --import-memory --initial-memory=%INITIAL_MEMORY_BYTES% --max-memory=%MAX_MEMORY_BYTES%"
)

for /f "delims=" %%i in ('odin.exe root') do set "ODIN_ROOT=%%i"
cp %ODIN_ROOT%/vendor/wgpu/wgpu.js bin/wgpu.js
cp %ODIN_ROOT%/core/sys/wasm/js/odin.js bin/odin.js
cp engine/audio/audio.js bin/audio.js

echo start a web server in bin to run it!!
