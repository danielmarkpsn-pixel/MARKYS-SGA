@echo off
title MARKYS SGA - Servidor de Rede Local
cd /d "%~dp0"
echo Iniciando o servidor local do MARKYS SGA...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0servidor-markys-sga.ps1"
if errorlevel 1 (
  echo.
  echo O servidor foi encerrado com erro. Confira as instrucoes de rede local.
  pause
)
