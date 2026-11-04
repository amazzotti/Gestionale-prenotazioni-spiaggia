@echo off
rem Rilascio di una nuova versione: vedi le istruzioni in rilascia.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rilascia.ps1" %*
pause
