@echo off
for %%a in ("bin\*.exe") do (
    echo deleting %%a
    del %%a
)

for %%a in ("bin\*.wasm") do (
    echo deleting %%a
    del %%a
)

del bin\*.js
del bin\cookies.dll
del bin\cookies.lib
del bin\cookies.exp
