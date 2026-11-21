@echo off
start "" powershell.exe -NoProfile -STA -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "%~dp0FieldKit.ps1"
