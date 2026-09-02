@echo off
title Assistente de Instalacao - Secure LAN File Transfer
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0setup_wizard.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Ocorreu um erro ao executar o assistente de instalacao.
    pause
)
