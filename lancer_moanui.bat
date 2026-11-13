@echo off
REM Lance Moanui sur Windows, sans droits administrateur.
REM Prerequis : uv (https://docs.astral.sh/uv/) installe pour l'utilisateur.
cd /d "%~dp0backend"
uv run --python 3.12 moanui
pause
