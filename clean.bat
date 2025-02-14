@echo off
for %%a in ("bin\*.exe") do (
    echo deleting %%a
    del %%a
)

for %%a in ("bin\*.wasm") do (
    echo deleting %%a
    del %%a
)
