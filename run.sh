#!/usr/bin/env bash
# Cria venv, instala dependências e roda o app.
set -e
cd "$(dirname "$0")"

if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt
python cameras_app/app.py
