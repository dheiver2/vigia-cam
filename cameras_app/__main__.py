"""Permite rodar com: python -m cameras_app"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import theme  # noqa: I001
from app import (  # noqa: I001
    CFG,
    CAMERAS_JSON,
    CONFIG_JSON,
    Janela,
    LoginDialog,
    carregar_config,
    parse_args,
)
from PySide6.QtWidgets import QApplication, QDialog  # noqa: I001

if __name__ == "__main__":
    args = parse_args()
    if args.config:
        CONFIG_JSON = args.config
    if args.cameras:
        CAMERAS_JSON = args.cameras
    CFG = carregar_config()

    if args.api:
        import uvicorn
        from api import app as fastapi_app
        print(f"Iniciando REST API na porta {args.api_port}...")
        uvicorn.run(fastapi_app, host="0.0.0.0", port=args.api_port)
    else:
        app = QApplication(sys.argv)
        app.setStyleSheet(theme.QSS)

        login = LoginDialog()
        login.setStyleSheet(theme.QSS)
        if login.exec() != QDialog.Accepted:
            sys.exit(0)

        janela = Janela(ia_inicial=not args.sem_ia, usuario=login.usuario_logado)
        sys.exit(app.exec())
