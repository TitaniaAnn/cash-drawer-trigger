@echo off
rem Launches the drawer button without leaving a console window open.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Open-CashDrawer.ps1"
