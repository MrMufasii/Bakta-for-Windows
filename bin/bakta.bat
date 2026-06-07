@echo off
setlocal
set "BIN=%~dp0"
set "APP=%BIN%.."
set "PATH=%BIN%;%BIN%blast\ncbi-blast-2.17.0+\bin;%APP%\perl\bin;%PATH%"
"%APP%\python\python.exe" -m bakta.main %*
