@echo off
set "APP=%~dp0"
set "PATH=%APP%bin;%APP%bin\blast\ncbi-blast-2.17.0+\bin;%APP%perl\bin;%PATH%"
echo Bakta for Windows - command prompt
echo   bakta --help
echo   bakta --db DBDIR\db-light -o out --threads 8 genome.fasta
echo   bakta_db download --type light --output DBDIR
echo.
cmd /k
