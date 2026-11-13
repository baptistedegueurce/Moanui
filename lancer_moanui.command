#!/bin/bash
# Lance Moanui sur macOS (double-clic), sans droits administrateur.
# Prérequis : uv (https://docs.astral.sh/uv/) installé pour l'utilisateur.
cd "$(dirname "$0")/backend" && uv run --python 3.12 moanui
