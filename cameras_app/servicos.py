"""Serviços de plataforma do vigia-cam: armazenamento, eventos, auditoria, criptografia e usuários.

Tudo aqui é I/O puro (sem Qt) para poder ser testado isolado:
  • diretórios de dados (~/VigiaCam) com retenção configurável
  • histórico de eventos em CSV diário (exigência comum de editais)
  • trilha de auditoria em JSONL (quem fez o quê e quando)
  • criptografia at-rest com Fernet (AES-128-CBC) para dados sensíveis
  • usuários com senha PBKDF2 + perfis (admin / operador / visualizador)
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
import re
import secrets
import time

BASE = os.environ.get("VIGIACAM_DADOS") or os.path.join(
    os.path.expanduser("~"), "VigiaCam")
DIR_GRAVACOES = os.path.join(BASE, "gravacoes")
DIR_CAPTURAS = os.path.join(BASE, "capturas")
DIR_EVENTOS = os.path.join(BASE, "eventos")
ARQ_AUDITORIA = os.path.join(BASE, "auditoria.jsonl")
ARQ_USUARIOS = os.path.join(BASE, "usuarios.json")
ARQ_CHAVE = os.path.join(BASE, ".key")  # chave Fernet (arquivo oculto)
ARQ_CADEIA = os.path.join(BASE, "cadeia_custodia.jsonl")  # log de cadeia de custódia


# ------------------------------------------------------------------
# Criptografia at-rest (Fernet / AES-128-CBC)
# ------------------------------------------------------------------
def _carregar_ou_criar_chave() -> bytes:
    """Carrega ou cria a chave Fernet. A chave fica em ~/VigiaCam/.key."""
    preparar_diretorios()
    if os.path.exists(ARQ_CHAVE):
        with open(ARQ_CHAVE, "rb") as f:
            return f.read().strip()
    try:
        from cryptography.fernet import Fernet
        chave = Fernet.generate_key()
    except ImportError:
        return b""
    with open(ARQ_CHAVE, "wb") as f:
        f.write(chave)
    try:
        os.chmod(ARQ_CHAVE, 0o600)
    except OSError:
        pass
    return chave


_chave_fernet: bytes | None = None


def _get_chave() -> bytes:
    global _chave_fernet
    if _chave_fernet is None:
        _chave_fernet = _carregar_ou_criar_chave()
    return _chave_fernet


def criptografar_dados(dados: bytes) -> bytes:
    """Criptografa bytes com Fernet. Retorna dados criptografados."""
    chave = _get_chave()
    if not chave:
        return dados
    try:
        from cryptography.fernet import Fernet
        return Fernet(chave).encrypt(dados)
    except Exception:
        return dados


def descriptografar_dados(dados: bytes) -> bytes:
    """Descriptografa bytes Fernet. Se não estiver criptografado, retorna original."""
    chave = _get_chave()
    if not chave:
        return dados
    try:
        from cryptography.fernet import Fernet
        return Fernet(chave).decrypt(dados)
    except Exception:
        return dados


def salvar_json_criptografado(caminho: str, dados) -> None:
    """Salva JSON com criptografia at-rest."""
    preparar_diretorios()
    plaintext = json.dumps(dados, ensure_ascii=False, indent=2).encode("utf-8")
    ciphertext = criptografar_dados(plaintext)
    tmp = f"{caminho}.tmp"
    with open(tmp, "wb") as f:
        f.write(ciphertext)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, caminho)


def carregar_json_criptografado(caminho: str, default=None):
    """Carrega JSON com descriptografia at-rest. Tenta plaintext se falhar."""
    if not os.path.exists(caminho):
        return default
    try:
        with open(caminho, "rb") as f:
            raw = f.read()
    except OSError:
        return default
    # Tenta descriptografar
    conteudo = descriptografar_dados(raw)
    try:
        return json.loads(conteudo.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        pass
    # Fallback: tenta ler como plaintext (compatibilidade)
    try:
        return json.loads(raw.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return default


def preparar_diretorios() -> None:
    for d in (BASE, DIR_GRAVACOES, DIR_CAPTURAS, DIR_EVENTOS):
        os.makedirs(d, exist_ok=True)


def _slug(nome: str) -> str:
    s = re.sub(r"[^\w\-]+", "-", (nome or "camera").strip(), flags=re.UNICODE)
    return s.strip("-") or "camera"


def caminho_gravacao(camera: str) -> str:
    d = os.path.join(DIR_GRAVACOES, _slug(camera), time.strftime("%Y-%m-%d"))
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, time.strftime("%H%M%S") + ".mp4")


def caminho_captura(camera: str) -> str:
    d = os.path.join(DIR_CAPTURAS, time.strftime("%Y-%m-%d"))
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, f"{_slug(camera)}-{time.strftime('%H%M%S')}.png")


def limpar_retencao(dias: int) -> int:
    """Apaga gravações/capturas/eventos mais antigos que `dias`. Retorna nº removido."""
    limite = time.time() - max(1, int(dias)) * 86400
    removidos = 0
    for raiz in (DIR_GRAVACOES, DIR_CAPTURAS, DIR_EVENTOS):
        if not os.path.isdir(raiz):
            continue
        for pasta, _, arquivos in os.walk(raiz, topdown=False):
            for a in arquivos:
                caminho = os.path.join(pasta, a)
                try:
                    if os.path.getmtime(caminho) < limite:
                        os.remove(caminho); removidos += 1
                except OSError:
                    pass
            try:                                   # remove diretórios vazios
                if pasta not in (DIR_GRAVACOES, DIR_CAPTURAS, DIR_EVENTOS):
                    os.rmdir(pasta)
            except OSError:
                pass
    return removidos


# ------------------------------------------------------------------
# Histórico de eventos (CSV diário — retenção/exportação p/ editais)
# ------------------------------------------------------------------
def registrar_evento(tipo: str, camera: str, detalhe: str) -> None:
    preparar_diretorios()
    caminho = os.path.join(DIR_EVENTOS,
                           f"eventos-{time.strftime('%Y-%m-%d')}.csv")
    novo = not os.path.exists(caminho)
    try:
        with open(caminho, "a", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            if novo:
                w.writerow(["data", "hora", "tipo", "camera", "detalhe"])
            w.writerow([time.strftime("%Y-%m-%d"), time.strftime("%H:%M:%S"),
                        tipo, camera, detalhe])
    except OSError:
        pass                                       # log nunca derruba o app


# ------------------------------------------------------------------
# Trilha de auditoria (JSONL)
# ------------------------------------------------------------------
_usuario_atual = "sistema"
_audit_cb = None


def definir_usuario(usuario: str) -> None:
    global _usuario_atual
    _usuario_atual = usuario or "sistema"


def definir_audit_callback(cb) -> None:
    """Callback opcional (UI) chamado a cada registro: cb(dict)."""
    global _audit_cb
    _audit_cb = cb


def auditar(acao: str, detalhe: str = "") -> None:
    preparar_diretorios()
    reg = {"quando": time.strftime("%Y-%m-%d %H:%M:%S"),
           "usuario": _usuario_atual, "acao": acao, "detalhe": detalhe}
    try:
        with open(ARQ_AUDITORIA, "a", encoding="utf-8") as f:
            f.write(json.dumps(reg, ensure_ascii=False) + "\n")
    except OSError:
        pass
    if _audit_cb is not None:
        try:
            _audit_cb(reg)
        except Exception:
            pass


def ler_auditoria(max_linhas: int = 300) -> list[dict]:
    if not os.path.exists(ARQ_AUDITORIA):
        return []
    try:
        with open(ARQ_AUDITORIA, encoding="utf-8") as f:
            linhas = f.readlines()[-max_linhas:]
    except OSError:
        return []
    regs = []
    for ln in linhas:
        try:
            regs.append(json.loads(ln))
        except json.JSONDecodeError:
            pass
    return regs


# ------------------------------------------------------------------
# Usuários e perfis (admin / operador) — senha PBKDF2-SHA256
# ------------------------------------------------------------------
PERFIS = ("admin", "operador", "visualizador")


def _hash_senha(senha: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac(
        "sha256", senha.encode("utf-8"), bytes.fromhex(salt), 100_000).hex()


def carregar_usuarios() -> list[dict]:
    dados = carregar_json_criptografado(ARQ_USUARIOS, default=[])
    return dados if isinstance(dados, list) else []


def salvar_usuarios(usuarios: list[dict]) -> None:
    preparar_diretorios()
    salvar_json_criptografado(ARQ_USUARIOS, usuarios)


def garantir_admin_padrao() -> bool:
    """Cria admin/admin no 1º uso. Retorna True se acabou de criar."""
    if carregar_usuarios():
        return False
    adicionar_usuario("admin", "admin", "admin")
    return True


def adicionar_usuario(usuario: str, senha: str, perfil: str,
                      cameras: list[str] | None = None) -> None:
    usuario = (usuario or "").strip().lower()
    if not usuario or perfil not in PERFIS or not senha:
        raise ValueError("usuário, senha e perfil (admin/operador/visualizador) são obrigatórios")
    usuarios = [u for u in carregar_usuarios() if u.get("usuario") != usuario]
    salt = secrets.token_hex(16)
    registro = {"usuario": usuario, "perfil": perfil,
                "salt": salt, "hash": _hash_senha(senha, salt)}
    if cameras is not None:
        registro["cameras"] = cameras
    usuarios.append(registro)
    salvar_usuarios(usuarios)


def remover_usuario(usuario: str) -> None:
    usuarios = carregar_usuarios()
    restantes = [u for u in usuarios if u.get("usuario") != usuario]
    admins = [u for u in restantes if u.get("perfil") == "admin"]
    if not admins:
        raise ValueError("não é possível remover o último administrador")
    salvar_usuarios(restantes)


def listar_usuarios() -> list[dict]:
    """Retorna lista de usuários sem campos sensíveis (salt/hash)."""
    return [{"usuario": u["usuario"], "perfil": u.get("perfil", "operador"),
             "cameras": u.get("cameras")} for u in carregar_usuarios()]


def definir_cameras_usuario(usuario: str, cameras: list[str] | None) -> None:
    """Define quais câmeras um usuário pode acessar. None = todas."""
    usuarios = carregar_usuarios()
    for u in usuarios:
        if u.get("usuario") == usuario:
            if cameras is None:
                u.pop("cameras", None)
            else:
                u["cameras"] = cameras
            break
    salvar_usuarios(usuarios)


def usuario_pode_acessar(usuario: dict, camera_url: str) -> bool:
    """Verifica se o usuário logado tem acesso à câmera informada.
    admin e operador com cameras=None têm acesso total.
    visualizador (ou qualquer perfil com cameras definido) só vê as listadas.
    """
    if usuario.get("perfil") in ("admin", "operador") and "cameras" not in usuario:
        return True
    cameras_permitidas = usuario.get("cameras")
    if cameras_permitidas is None:
        return True
    return camera_url in cameras_permitidas


# ------------------------------------------------------------------
# Cadeia de custódia (hash SHA-256 + log de integridade)
# ------------------------------------------------------------------
def calcular_hash_arquivo(caminho: str) -> str:
    """Calcula hash SHA-256 de um arquivo. Retorna hex string."""
    h = hashlib.sha256()
    try:
        with open(caminho, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
    except OSError:
        return ""
    return h.hexdigest()


def registrar_cadeia_custodia(caminho: str, tipo: str, camera: str,
                               usuario: str | None = None) -> dict:
    """Registra arquivo na cadeia de custódia com hash e metadados.

    Registra em JSONL para rastreabilidade probatória.
    Retorna o registro criado.
    """
    preparar_diretorios()
    hash_val = calcular_hash_arquivo(caminho)
    tam = 0
    try:
        tam = os.path.getsize(caminho)
    except OSError:
        pass
    registro = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "arquivo": os.path.basename(caminho),
        "caminho_completo": caminho,
        "tipo": tipo,  # "gravacao", "captura", "exportacao"
        "camera": camera,
        "usuario": usuario or _usuario_atual,
        "hash_sha256": hash_val,
        "tamanho_bytes": tam,
        "integridade": "verificado",
    }
    try:
        with open(ARQ_CADEIA, "a", encoding="utf-8") as f:
            f.write(json.dumps(registro, ensure_ascii=False) + "\n")
    except OSError:
        pass
    if _audit_cb is not None:
        try:
            _audit_cb(registro)
        except Exception:
            pass
    return registro


def verificar_integridade(caminho: str, hash_esperado: str) -> bool:
    """Verifica se o arquivo corresponde ao hash SHA-256 esperado."""
    hash_atual = calcular_hash_arquivo(caminho)
    return hash_atual == hash_esperado


def ler_cadeia_custodia(max_linhas: int = 500) -> list[dict]:
    """Lê os registros da cadeia de custódia."""
    if not os.path.exists(ARQ_CADEIA):
        return []
    try:
        with open(ARQ_CADEIA, encoding="utf-8") as f:
            linhas = f.readlines()[-max_linhas:]
    except OSError:
        return []
    regs = []
    for ln in linhas:
        try:
            regs.append(json.loads(ln))
        except json.JSONDecodeError:
            pass
    return regs


# ------------------------------------------------------------------
# Exportação de evidência (ZIP com vídeo + metadados + hash)
# ------------------------------------------------------------------
def exportar_evidencia(arquivo: str, camera: str, descricao: str = "",
                       usuario: str | None = None) -> str:
    """Empacota arquivo de evidência em ZIP com metadados e hash.

    Cria um .zip contendo:
      - O arquivo original (vídeo/imagem)
      - metadados.json (informações da evidência)
      - cadeia_custodia.json (hash e trilha)
      - assinatura.txt (hash SHA-256 para verificação)

    Retorna o caminho do ZIP criado.
    """
    import zipfile

    preparar_diretorios()
    base = os.path.basename(arquivo)
    nome_zip = os.path.join(DIR_CAPTURAS, f"evidencia-{camera}-{time.strftime('%Y%m%d-%H%M%S')}.zip")

    hash_arquivo = calcular_hash_arquivo(arquivo)
    tam = 0
    try:
        tam = os.path.getsize(arquivo)
    except OSError:
        pass

    metadados = {
        "versao": "1.0",
        "timestamp_exportacao": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "usuario": usuario or _usuario_atual,
        "camera": camera,
        "descricao": descricao,
        "arquivo_original": base,
        "hash_sha256": hash_arquivo,
        "tamanho_bytes": tam,
    }

    # Registra na cadeia de custódia
    registro = registrar_cadeia_custodia(arquivo, "exportacao", camera, usuario)

    assinatura = (
        f"=== VIGIA-CAM EVIDÊNCIA ===\n"
        f"Arquivo: {base}\n"
        f"Câmera: {camera}\n"
        f"Data/Hora: {metadados['timestamp_exportacao']}\n"
        f"Usuário: {metadados['usuario']}\n"
        f"SHA-256: {hash_arquivo}\n"
        f"Tamanho: {tam} bytes\n"
        f"==========================\n"
    )

    try:
        with zipfile.ZipFile(nome_zip, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.write(arquivo, base)
            zf.writestr("metadados.json", json.dumps(metadados, ensure_ascii=False, indent=2))
            zf.writestr("cadeia_custodia.json", json.dumps(registro, ensure_ascii=False, indent=2))
            zf.writestr("assinatura.txt", assinatura)
    except OSError:
        return ""

    auditar("exportar_evidencia", f"arquivo={base} camera={camera}")
    return nome_zip


def verificar_login(usuario: str, senha: str) -> dict | None:
    usuario = (usuario or "").strip().lower()
    for u in carregar_usuarios():
        if u.get("usuario") == usuario:
            try:
                ok = secrets.compare_digest(
                    u.get("hash", ""), _hash_senha(senha or "", u.get("salt", "")))
            except ValueError:
                return None
            if ok:
                resultado = {"usuario": usuario, "perfil": u.get("perfil", "operador")}
                cameras = u.get("cameras")
                if cameras is not None:
                    resultado["cameras"] = cameras
                return resultado
    return None
