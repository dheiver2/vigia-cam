"""REST API do vigia-cam — FastAPI.

Endpoints:
  GET  /health              — health check
  GET  /api/v1/status       — status geral (câmeras online, versão, etc.)
  GET  /api/v1/cameras      — lista de câmeras
  GET  /api/v1/eventos      — eventos recentes
  GET  /api/v1/auditoria    — trilha de auditoria
  GET  /api/v1/cadeia       — cadeia de custódia
  POST /api/v1/login        — autenticação (retorna JWT)

Uso: uvicorn api:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import os
import sys
import time
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import servicos
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(
    title="VigiaCam API",
    description="API REST para monitoramento de câmeras com IA",
    version="1.2.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ------------------------------------------------------------------
# Modelos Pydantic
# ------------------------------------------------------------------
class LoginRequest(BaseModel):
    usuario: str
    senha: str


class LoginResponse(BaseModel):
    token: str
    usuario: str
    perfil: str


class CameraResponse(BaseModel):
    nome: str
    categoria: str
    tipo: str
    url: str


class EventoResponse(BaseModel):
    data: str
    hora: str
    tipo: str
    camera: str
    detalhe: str


class StatusResponse(BaseModel):
    versao: str
    uptime_segundos: float
    total_cameras: int
    usuarios_cadastrados: int
    status: str


# ------------------------------------------------------------------
# Tokens simples (em produção, usar JWT)
# ------------------------------------------------------------------
_tokens: dict[str, dict] = {}  # token -> {usuario, perfil, expiracao}


def _gerar_token(usuario: str, perfil: str) -> str:
    import secrets
    token = secrets.token_urlsafe(32)
    _tokens[token] = {
        "usuario": usuario,
        "perfil": perfil,
        "expiracao": datetime.now() + timedelta(hours=8),
    }
    return token


def _verificar_token(authorization: str | None = Header(None)) -> dict:
    if not authorization:
        raise HTTPException(status_code=401, detail="Token não fornecido")
    token = authorization.replace("Bearer ", "")
    dados = _tokens.get(token)
    if not dados:
        raise HTTPException(status_code=401, detail="Token inválido")
    if datetime.now() > dados["expiracao"]:
        del _tokens[token]
        raise HTTPException(status_code=401, detail="Token expirado")
    return dados


# ------------------------------------------------------------------
# Startup
# ------------------------------------------------------------------
@app.on_event("startup")
async def startup():
    servicos.preparar_diretorios()
    servicos.garantir_admin_padrao()


# ------------------------------------------------------------------
# Endpoints
# ------------------------------------------------------------------
@app.get("/health")
async def health():
    return {"status": "ok", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S")}


@app.get("/api/v1/status", response_model=StatusResponse)
async def status():
    usuarios = servicos.listar_usuarios()
    cameras = servicos.carregar_json_criptografado(
        os.environ.get("VIGIACAM_CAMERAS") or
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "cameras.json"),
        default=[]
    )
    return StatusResponse(
        versao="1.2.0",
        uptime_segundos=0,
        total_cameras=len(cameras) if isinstance(cameras, list) else 0,
        usuarios_cadastrados=len(usuarios),
        status="operacional",
    )


@app.get("/api/v1/cameras", response_model=list[CameraResponse])
async def listar_cameras(usuario: dict = Depends(_verificar_token)):
    raw = servicos.carregar_json_criptografado(
        os.environ.get("VIGIACAM_CAMERAS") or
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "cameras.json"),
        default=[]
    )
    cameras = []
    if isinstance(raw, list):
        for c in raw:
            url = c.get("url", "")
            if servicos.usuario_pode_acessar(usuario, url):
                cameras.append(CameraResponse(
                    nome=c.get("nome", url),
                    categoria=c.get("categoria", "Outras"),
                    tipo=c.get("tipo", "rtsp"),
                    url=url,
                ))
    return cameras


@app.get("/api/v1/eventos")
async def listar_eventos(dias: int = 1, usuario: dict = Depends(_verificar_token)):
    eventos = []
    for i in range(max(1, dias)):
        d = datetime.now() - timedelta(days=i)
        nome = f"eventos-{d.strftime('%Y-%m-%d')}.csv"
        caminho = os.path.join(servicos.DIR_EVENTOS, nome)
        if os.path.exists(caminho):
            try:
                import csv
                with open(caminho, encoding="utf-8") as f:
                    reader = csv.DictReader(f)
                    for row in reader:
                        eventos.append(row)
            except OSError:
                pass
    return eventos[:500]


@app.get("/api/v1/auditoria")
async def listar_auditoria(linhas: int = 100, usuario: dict = Depends(_verificar_token)):
    if usuario.get("perfil") != "admin":
        raise HTTPException(status_code=403, detail="Apenas administradores")
    return servicos.ler_auditoria(linhas)


@app.get("/api/v1/cadeia")
async def listar_cadeia(linhas: int = 100, usuario: dict = Depends(_verificar_token)):
    if usuario.get("perfil") != "admin":
        raise HTTPException(status_code=403, detail="Apenas administradores")
    return servicos.ler_cadeia_custodia(linhas)


@app.post("/api/v1/login", response_model=LoginResponse)
async def login(req: LoginRequest):
    servicos.preparar_diretorios()
    servicos.garantir_admin_padrao()
    resultado = servicos.verificar_login(req.usuario, req.senha)
    if resultado is None:
        raise HTTPException(status_code=401, detail="Credenciais inválidas")
    token = _gerar_token(resultado["usuario"], resultado["perfil"])
    servicos.definir_usuario(resultado["usuario"])
    servicos.auditar("login_api", f"usuario={resultado['usuario']}")
    return LoginResponse(
        token=token,
        usuario=resultado["usuario"],
        perfil=resultado["perfil"],
    )


@app.get("/api/v1/verificar-hash")
async def verificar_hash(caminho: str, hash_esperado: str,
                          usuario: dict = Depends(_verificar_token)):
    if usuario.get("perfil") != "admin":
        raise HTTPException(status_code=403, detail="Apenas administradores")
    ok = servicos.verificar_integridade(caminho, hash_esperado)
    return {"integridade_verificada": ok, "arquivo": caminho}
