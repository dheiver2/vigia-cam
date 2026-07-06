#!/usr/bin/env python3
"""vigia-cam — plataforma de monitoramento de câmeras ao vivo (RTSP/HLS)
com detecção de objetos (YOLOv8n). UI black premium em PySide6.

Navegação por funcionalidades (estilo VMS):
  • Ao Vivo      — videowall por categoria (HUD sobreposto), clique p/ ampliar,
                   captura de imagem e gravação manual/por evento
  • Eventos      — log em tempo real (detecções + quedas), filtro e export CSV;
                   histórico persistido em ~/VigiaCam/eventos
  • Dashboard    — métricas agregadas + saúde/disponibilidade por câmera
  • Câmeras      — gestão da lista (adicionar / remover) -> cameras.json
  • Auditoria    — trilha de quem fez o quê (login, exportações, gravações…)
  • Configurações— performance/IA, retenção e usuários -> config.json

Controle de acesso: login obrigatório com perfis admin/operador.
Só o mural da categoria selecionada roda threads de captura.
Uso apenas com streams que você tem autorização para acessar.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections import OrderedDict, defaultdict, deque

import cv2
import servicos
import theme
from detector import Detector
from PySide6.QtCore import QPointF, Qt, QThread, QTimer, Signal, Slot
from PySide6.QtGui import (
    QBrush,
    QColor,
    QImage,
    QLinearGradient,
    QPainter,
    QPen,
    QPixmap,
    QPolygonF,
)
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QDialog,
    QFileDialog,
    QFormLayout,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QHeaderView,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QScrollArea,
    QSpinBox,
    QStackedWidget,
    QTableWidget,
    QTableWidgetItem,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

__version__ = "1.2.0"

AQUI = os.path.dirname(os.path.abspath(__file__))
CAMERAS_JSON = os.environ.get("VIGIACAM_CAMERAS") or os.path.join(AQUI, "cameras.json")
CONFIG_JSON = os.environ.get("VIGIACAM_CONFIG") or os.path.join(AQUI, "config.json")


class LoginDialog(QDialog):
    """Tela de login obrigatório (RBAC) — UI polida."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("vigia-cam — Login")
        self.setFixedSize(440, 340)
        self.usuario_logado = None

        lay = QVBoxLayout(self)
        lay.setContentsMargins(44, 36, 44, 28)
        lay.setSpacing(4)

        logo = QLabel("VIGIA")
        logo.setObjectName("loginTitle")
        logo.setAlignment(Qt.AlignCenter)
        lay.addWidget(logo)

        dot = QLabel("•CAM")
        dot.setObjectName("loginSubtitle")
        dot.setAlignment(Qt.AlignCenter)
        dot.setStyleSheet(f"color:{theme.ACCENT}; font-size:14px; font-weight:800; letter-spacing:2px;")
        lay.addWidget(dot)

        sub = QLabel("Acesso restrito ao sistema de monitoramento")
        sub.setObjectName("loginSubtitle")
        sub.setAlignment(Qt.AlignCenter)
        lay.addWidget(sub)

        lay.addSpacing(24)

        lbl_user = QLabel("Usuário")
        lbl_user.setStyleSheet(f"color:{theme.MUTED}; font-size:11px; font-weight:600; letter-spacing:0.5px;")
        lay.addWidget(lbl_user)
        self.in_user = QLineEdit()
        self.in_user.setPlaceholderText("admin")
        self.in_user.setFixedHeight(38)
        self.in_user.setTooltip("Digite seu nome de usuário")
        lay.addWidget(self.in_user)

        lay.addSpacing(8)

        lbl_senha = QLabel("Senha")
        lbl_senha.setStyleSheet(f"color:{theme.MUTED}; font-size:11px; font-weight:600; letter-spacing:0.5px;")
        lay.addWidget(lbl_senha)
        self.in_senha = QLineEdit()
        self.in_senha.setEchoMode(QLineEdit.Password)
        self.in_senha.setPlaceholderText("••••••••")
        self.in_senha.setFixedHeight(38)
        self.in_senha.setTooltip("Digite sua senha")
        self.in_senha.returnPressed.connect(self._autenticar)
        lay.addWidget(self.in_senha)

        self.erro = QLabel("")
        self.erro.setObjectName("loginErro")
        self.erro.setAlignment(Qt.AlignCenter)
        lay.addWidget(self.erro)

        lay.addSpacing(12)

        btn = QPushButton("Entrar")
        btn.setObjectName("loginBtn")
        btn.setFixedHeight(44)
        btn.setTooltip("Enter")
        btn.clicked.connect(self._autenticar)
        lay.addWidget(btn)

        lay.addStretch()

        info = QLabel("Credenciais padrão: admin / admin")
        info.setObjectName("loginSubtitle")
        info.setAlignment(Qt.AlignCenter)
        info.setStyleSheet(f"color:{theme.MUTED}; font-size:10px; font-style:italic;")
        lay.addWidget(info)

        self.in_user.setFocus()

    def _autenticar(self):
        user = self.in_user.text().strip()
        senha = self.in_senha.text()
        if not user or not senha:
            self.erro.setText("Preencha usuário e senha")
            return
        servicos.preparar_diretorios()
        servicos.garantir_admin_padrao()
        resultado = servicos.verificar_login(user, senha)
        if resultado is None:
            self.erro.setText("Credenciais inválidas")
            self.in_senha.clear()
            self.in_senha.setFocus()
            return
        self.usuario_logado = resultado
        servicos.definir_usuario(user)
        servicos.auditar("login", f"perfil={resultado.get('perfil')}")
        self.accept()


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        prog="vigia-cam",
        description="Monitoramento de câmeras RTSP/HLS com detecção de objetos (YOLOv8n).",
    )
    p.add_argument("--config", help="Caminho alternativo para config.json")
    p.add_argument("--cameras", help="Caminho alternativo para cameras.json")
    p.add_argument("--sem-ia", action="store_true", help="Inicia com a detecção de IA desligada")
    p.add_argument("--api", action="store_true", help="Inicia a REST API (FastAPI/uvicorn)")
    p.add_argument("--api-port", type=int, default=8000, help="Porta da REST API (default: 8000)")
    p.add_argument("--version", action="version", version=f"vigia-cam {__version__}")
    return p.parse_args(argv)


CFG_PADRAO = {
    "detectar_a_cada": 4, "imgsz": 480, "confianca": 0.4,
    "fps_max": 20, "classes": None, "colunas": 2, "reconectar_seg": 3,
    "display_max_w": 720,
    "retencao_dias": 30, "gravar_evento": True, "pos_evento_seg": 8,
    "privacy_masks": {},
}

# Limites aceitos por chave: (mínimo, máximo). Valores fora são "clampados"
# para a faixa válida em vez de derrubar o app ou degradar a performance.
CFG_LIMITES = {
    "detectar_a_cada": (1, 30), "imgsz": (160, 1280), "confianca": (0.05, 0.95),
    "fps_max": (1, 60), "colunas": (1, 4), "reconectar_seg": (1, 60),
    "display_max_w": (160, 3840),
    "retencao_dias": (1, 365), "pos_evento_seg": (2, 60),
}


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def validar_config(bruto: dict) -> dict:
    """Mescla com os padrões aceitando só valores do tipo certo e na faixa.

    Entradas inválidas (tipo errado, fora do range) caem no padrão/limite em
    vez de propagar até o pipeline de captura e quebrar tudo lá na frente.
    """
    cfg = dict(CFG_PADRAO)
    if not isinstance(bruto, dict):
        return cfg
    for chave, padrao in CFG_PADRAO.items():
        if chave not in bruto:
            continue
        valor = bruto[chave]
        if chave == "classes":                         # None ou lista de ints
            if valor is None or (isinstance(valor, list)
                                 and all(isinstance(x, int) for x in valor)):
                cfg[chave] = valor
            continue
        if isinstance(padrao, bool):                   # chaves booleanas
            if isinstance(valor, bool):
                cfg[chave] = valor
            continue
        if not isinstance(valor, (int, float)) or isinstance(valor, bool):
            continue                                   # tipo errado -> mantém padrão
        if chave in CFG_LIMITES:
            lo, hi = CFG_LIMITES[chave]
            valor = _clamp(valor, lo, hi)
        cfg[chave] = valor
    # imgsz precisa ser múltiplo de 32 p/ o YOLO; ajusta sem reclamar
    cfg["imgsz"] = int(round(cfg["imgsz"] / 32)) * 32 or 32
    return cfg


def carregar_config() -> dict:
    dados = servicos.carregar_json_criptografado(CONFIG_JSON, default=None)
    if dados is not None:
        return validar_config(dados)
    return dict(CFG_PADRAO)


def _escrever_json_atomico(caminho, dados):
    """Escreve via arquivo temporário + rename atômico.

    Um crash no meio da escrita deixaria o JSON truncado/corrompido; o rename
    é atômico no POSIX, então ou o arquivo antigo permanece, ou o novo completo.
    """
    tmp = f"{caminho}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, caminho)


def salvar_config(cfg: dict) -> None:
    servicos.salvar_json_criptografado(CONFIG_JSON, cfg)


def _normalizar_camera(c: dict) -> dict | None:
    """Valida/normaliza uma entrada de câmera. Retorna dict ou None se inválida."""
    if not isinstance(c, dict):
        return None
    url = str(c.get("url", "")).strip()
    if not validar_url(url):
        return None
    nome = str(c.get("nome", "")).strip() or url
    categoria = str(c.get("categoria", "")).strip() or "Outras"
    tipo = "rtsp" if url.lower().startswith("rtsp") else "hls"
    return {"nome": nome, "categoria": categoria, "tipo": tipo, "url": url}


def carregar_cameras() -> list[dict]:
    bruto = servicos.carregar_json_criptografado(CAMERAS_JSON, default=None)
    if bruto is None:
        return []
    if not isinstance(bruto, list):
        return []
    cams = []
    for c in bruto:
        nc = _normalizar_camera(c)
        if nc is not None:
            cams.append(nc)
    return cams


def salvar_cameras(cams: list[dict]) -> None:
    servicos.salvar_json_criptografado(CAMERAS_JSON, cams)


ESQUEMAS_VALIDOS = ("rtsp://", "rtsps://", "http://", "https://")


def validar_url(url: str) -> bool:
    """Aceita só RTSP(S) ou HTTP(S). HTTP precisa apontar p/ playlist HLS.

    Bloqueia esquemas perigosos (file://, etc.) e URLs vazias/sem host.
    """
    url = (url or "").strip()
    low = url.lower()
    if not low.startswith(ESQUEMAS_VALIDOS):
        return False
    resto = url.split("://", 1)[1] if "://" in url else ""
    if not resto or resto.startswith("/"):     # precisa ter host
        return False
    if low.startswith(("http://", "https://")) and ".m3u8" not in low:
        return False                           # HTTP só faz sentido como HLS aqui
    return True


def agrupar_por_categoria(cameras: list[dict]) -> OrderedDict:
    grupos = OrderedDict()
    for c in cameras:
        grupos.setdefault(c.get("categoria", "Outras"), []).append(c)
    return grupos


CFG = carregar_config()
COLUNAS = CFG["colunas"]


# ====================================================================
# Captura
# ====================================================================
class CapturaThread(QThread):
    frame_pronto = Signal(int, QImage)
    status = Signal(int, dict, bool)   # (idx, contagem, online)

    def __init__(self, idx, url, detector=None, privacy_mask=None):
        super().__init__()
        self.idx = idx
        self.url = url
        self.detector = detector
        self.privacy_mask = privacy_mask or []
        self._rodando = True
        self._intervalo = 1.0 / max(1, CFG["fps_max"])
        self._detect_a_cada = max(1, CFG["detectar_a_cada"])
        self._max_w = int(CFG.get("display_max_w", 720))

    def _abrir(self):
        cap = cv2.VideoCapture(self.url, cv2.CAP_FFMPEG)
        try:
            cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        except Exception:
            pass
        return cap

    MAX_READ_FAILS = 5          # leituras falhas seguidas antes de reabrir

    def run(self):
        cap = self._abrir()
        dets, contador, ultimo_emit = [], 0, 0.0
        reconexoes = 0                               # p/ escalar o backoff
        read_fails = 0                               # leituras falhas seguidas
        base = max(1, int(CFG["reconectar_seg"]))
        while self._rodando:
            if cap is None or not cap.isOpened():
                self.status.emit(self.idx, {}, False)
                # backoff progressivo (base, 2×, 4×… até 30s) p/ não martelar
                # a CPU/rede quando a câmera está fora do ar.
                espera = min(base * (2 ** min(reconexoes, 4)), 30)
                self.msleep(int(espera * 1000))
                if not self._rodando:
                    break
                reconexoes += 1
                cap = self._abrir()
                continue
            ok, frame = cap.read()
            if not ok or frame is None:
                # tolera drops transientes; só reabre após várias falhas seguidas
                read_fails += 1
                if read_fails >= self.MAX_READ_FAILS:
                    cap.release(); cap = None
                    self.status.emit(self.idx, {}, False)
                else:
                    self.msleep(30)
                continue
            read_fails = 0
            reconexoes = 0                           # leitura ok -> zera backoff
            # só reduz se for bem maior que o alvo (ex.: 1080p) — abaixo disso
            # o custo do resize supera o ganho (medido), então deixa passar
            h0, w0 = frame.shape[:2]
            if w0 > self._max_w * 1.5:
                frame = cv2.resize(frame, (self._max_w, int(h0 * self._max_w / w0)),
                                   interpolation=cv2.INTER_AREA)
            contagem = {}
            if self.detector is not None:
                try:
                    if contador % self._detect_a_cada == 0:
                        dets = self.detector.detectar(frame)
                    frame, contagem = self.detector.desenhar(frame, dets)
                except Exception:
                    pass
            if self.privacy_mask:
                try:
                    frame = Detector.aplicar_privacy_mask(frame, self.privacy_mask)
                except Exception:
                    pass
            contador += 1
            agora = time.monotonic()
            if agora - ultimo_emit >= self._intervalo:
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                h, w, _ = rgb.shape
                img = QImage(rgb.data, w, h, 3 * w, QImage.Format_RGB888).copy()
                self.frame_pronto.emit(self.idx, img)
                self.status.emit(self.idx, contagem, True)
                ultimo_emit = agora
        if cap is not None:
            cap.release()

    def parar(self):
        self._rodando = False
        self.wait(3000)


# ====================================================================
# Card + Mural (Ao Vivo)
# ====================================================================
class CameraCard(QFrame):
    """Card de câmera com tooltip, badge de status e detecção."""

    clicado = Signal(object)

    def __init__(self):
        super().__init__()
        self.cam = None
        self.setObjectName("cameraTile")
        self.setStyleSheet("QFrame#cameraTile { background: transparent; border: none; }")
        self._frames = 0
        self._t0 = None
        self.mirror = None

        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0); lay.setSpacing(0)

        self.nome = QLabel(""); self.nome.setObjectName("camName"); self.nome.hide()
        self.badge = QLabel("• OFFLINE"); self.badge.setObjectName("offBadge"); self.badge.hide()
        self.meta = QLabel(""); self.meta.setObjectName("camMeta"); self.meta.hide()
        self.video = QLabel("—")
        self.video.setAlignment(Qt.AlignCenter)
        self.video.setStyleSheet("background:#000; color:#666;")
        self.video.setMinimumSize(220, 140)
        self.video.setTooltip("Clique para ampliar")
        lay.addWidget(self.video, 1)
        self.chips = QLabel(""); self.chips.setObjectName("detChips"); self.chips.hide()
        self.fps = QLabel(""); self.fps.setObjectName("fps"); self.fps.hide()

    def bind(self, cam):
        self.cam = cam
        self.mirror = None
        self._frames = 0; self._t0 = None
        self.video.setPixmap(QPixmap())
        if cam is None:
            self.nome.setText(""); self.meta.setText("")
            self.video.setText("—"); self.chips.setText(""); self.fps.setText("")
            self.badge.setText(""); self.badge.setObjectName("offBadge")
            self.setTooltip("")
        else:
            self.nome.setText(cam["nome"])
            self.meta.setText(f"{cam.get('tipo','?').upper()} · {cam.get('categoria','')}")
            self.video.setText("conectando…"); self.chips.setText(""); self.fps.setText("")
            self.badge.setText("• OFFLINE"); self.badge.setObjectName("offBadge")
            self.setTooltip(f"{cam['nome']}\n{cam.get('tipo','?').upper()} · {cam.get('categoria','')}")
        self.badge.style().unpolish(self.badge); self.badge.style().polish(self.badge)
        self.setVisible(cam is not None)

    def mousePressEvent(self, e):
        if self.cam is not None:
            self.clicado.emit(self)

    def set_frame(self, img):
        self._frames += 1
        agora = time.monotonic()
        if self._t0 is None:
            self._t0 = agora
        elif agora - self._t0 >= 1.0:
            self.fps.setText(f"{self._frames / (agora - self._t0):.0f} fps")
            self._frames = 0; self._t0 = agora
        pix = QPixmap.fromImage(img)
        self.video.setPixmap(pix.scaled(
            self.video.size(), Qt.KeepAspectRatio, Qt.FastTransformation))
        if self.mirror is not None:
            vlabel, clabel = self.mirror
            vlabel.setPixmap(pix.scaled(
                vlabel.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation))
            clabel.setText(self.chips.text())

    def set_status(self, contagem, online):
        if online:
            self.badge.setText("● AO VIVO"); self.badge.setObjectName("liveBadge")
        else:
            self.badge.setText("● OFFLINE"); self.badge.setObjectName("offBadge")
            self.video.setText("sem sinal")
        self.badge.style().unpolish(self.badge); self.badge.style().polish(self.badge)
        self.chips.setText("  ".join(f"{k} {v}" for k, v in contagem.items()))


class MuralWidget(QWidget):
    """Mural paginado com layout selecionável (1×1…4×4).

    Reaproveita um POOL de cards do tamanho da página; só as câmeras
    da página atual têm thread rodando. Assim 4 ou 400 câmeras custam
    o mesmo: no máximo `tiles_por_pagina` streams ativos por vez.
    """

    evento = Signal(str, dict, bool)
    pagina_mudou = Signal()            # avisa p/ fechar o viewer ampliado
    LAYOUTS = OrderedDict([("1×1", 1), ("2×2", 4), ("3×3", 9), ("4×4", 16)])

    def __init__(self, cameras, get_detector, ao_clicar):
        super().__init__()
        self.cameras = cameras
        self.get_detector = get_detector
        self._ao_clicar = ao_clicar
        self.threads = []
        self.pool = []
        self._ativo = False
        self.page = 0
        self.tiles = 4
        self.cols = 2

        col = QVBoxLayout(self); col.setContentsMargins(12, 8, 12, 12); col.setSpacing(8)

        bar = QHBoxLayout()
        bar.setSpacing(8)
        lbl_layout = QLabel("Layout")
        lbl_layout.setStyleSheet(f"color:{theme.MUTED}; font-size:11px; font-weight:600;")
        bar.addWidget(lbl_layout)
        self.cb_layout = QComboBox(); self.cb_layout.addItems(self.LAYOUTS.keys())
        self.cb_layout.setCurrentText("2×2")
        self.cb_layout.currentTextChanged.connect(self._mudar_layout)
        self.cb_layout.setFixedWidth(80)
        bar.addWidget(self.cb_layout)
        bar.addSpacing(20)

        self.btn_prev = QPushButton("‹")
        self.btn_prev.setFixedSize(32, 32)
        self.btn_prev.setTooltip("Página anterior (←)")
        self.btn_prev.clicked.connect(lambda: self._ir(self.page - 1))
        self.lbl_pag = QLabel("")
        self.lbl_pag.setObjectName("camMeta")
        self.lbl_pag.setStyleSheet(f"color:{theme.TEXT}; font-size:12px; font-weight:700; padding:0 8px;")
        self.btn_next = QPushButton("›")
        self.btn_next.setFixedSize(32, 32)
        self.btn_next.setTooltip("Próxima página (→)")
        self.btn_next.clicked.connect(lambda: self._ir(self.page + 1))
        bar.addWidget(self.btn_prev); bar.addWidget(self.lbl_pag); bar.addWidget(self.btn_next)
        bar.addStretch(1)
        self.lbl_total = QLabel(f"{len(cameras)} câmeras")
        self.lbl_total.setObjectName("camMeta")
        self.lbl_total.setStyleSheet(f"color:{theme.MUTED}; font-size:11px;")
        bar.addWidget(self.lbl_total)
        col.addLayout(bar)

        # ---- área rolável com a grade ----
        self.grid_host = QWidget()
        self.grade = QGridLayout(self.grid_host)
        self.grade.setSpacing(4)
        scroll = QScrollArea(); scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.NoFrame)
        scroll.setWidget(self.grid_host)
        col.addWidget(scroll, 1)

        self._rebuild_pool()

    # ---------- layout / pool ----------
    def _rebuild_pool(self):
        for c in self.pool:
            c.setParent(None)
        self.pool.clear()
        self.cols = max(1, int(self.tiles ** 0.5))
        for i in range(self.tiles):
            card = CameraCard()
            card.clicado.connect(self._ao_clicar)
            self.pool.append(card)
            self.grade.addWidget(card, i // self.cols, i % self.cols)
        self._refresh_page()

    def _n_paginas(self):
        return max(1, (len(self.cameras) + self.tiles - 1) // self.tiles)

    def _page_cams(self):
        ini = self.page * self.tiles
        return self.cameras[ini:ini + self.tiles]

    def _refresh_page(self):
        cams = self._page_cams()
        for i, card in enumerate(self.pool):
            card.bind(cams[i] if i < len(cams) else None)
        self.lbl_pag.setText(f"Página {self.page + 1}/{self._n_paginas()}")
        self.btn_prev.setEnabled(self.page > 0)
        self.btn_next.setEnabled(self.page < self._n_paginas() - 1)

    def _mudar_layout(self, txt):
        self.tiles = self.LAYOUTS.get(txt, 4)
        self.page = min(self.page, self._n_paginas() - 1)
        ativo = self._ativo
        if ativo:
            self._parar_threads()
        self._rebuild_pool()
        if ativo:
            self._iniciar_threads()
        self.pagina_mudou.emit()

    def _ir(self, page):
        page = max(0, min(page, self._n_paginas() - 1))
        if page == self.page:
            return
        ativo = self._ativo
        if ativo:
            self._parar_threads()
        self.page = page
        self._refresh_page()
        if ativo:
            self._iniciar_threads()
        self.pagina_mudou.emit()

    # ---------- threads (só a página visível) ----------
    def iniciar(self):
        if self._ativo:
            return
        self._ativo = True
        self._iniciar_threads()

    def _iniciar_threads(self):
        det = self.get_detector()
        masks = CFG.get("privacy_masks", {})
        for i, cam in enumerate(self._page_cams()):
            mask = masks.get(cam["url"], [])
            t = CapturaThread(i, cam["url"], det, privacy_mask=mask)
            t.frame_pronto.connect(self._frame)
            t.status.connect(self._status)
            t.start()
            self.threads.append(t)

    def reiniciar(self):
        """Para e sobe de novo as threads (aplica detector novo, etc.)."""
        if not self._ativo:
            return
        self._parar_threads()
        self._iniciar_threads()

    def parar(self):
        if not self._ativo:
            return
        self._ativo = False
        self._parar_threads()

    def _parar_threads(self):
        # Bug 2 + 3: desliga signals (evita frame zumbi no card errado) e
        # sinaliza parada em TODAS antes de esperar (evita freeze sequencial).
        for t in self.threads:
            for sig in (t.frame_pronto, t.status):
                try:
                    sig.disconnect()
                except (RuntimeError, TypeError):
                    pass
            t._rodando = False
        for t in self.threads:
            t.wait(3000)
        self.threads.clear()

    @Slot(int, QImage)
    def _frame(self, idx, img):
        if idx < len(self.pool):
            self.pool[idx].set_frame(img)

    @Slot(int, dict, bool)
    def _status(self, idx, contagem, online):
        if idx >= len(self.pool):
            return
        card = self.pool[idx]
        if card.cam is None:
            return
        card.set_status(contagem, online)
        self.evento.emit(card.cam["nome"], contagem, online)


# ====================================================================
# Seções de funcionalidade
# ====================================================================
class AoVivoSection(QWidget):
    """Sub-abas por categoria + viewer ampliado."""

    def __init__(self, grupos, get_detector, on_evento):
        super().__init__()
        self.murais = []
        self._ampliado = None
        lay = QVBoxLayout(self); lay.setContentsMargins(0, 0, 0, 0)
        self.stack = QStackedWidget(); lay.addWidget(self.stack)

        self.tabs = QTabWidget(); self.tabs.setObjectName("subnav")
        self.tabs.setMovable(True); self.tabs.setDocumentMode(True)
        for nome, cams in grupos.items():
            m = MuralWidget(cams, get_detector, self._ampliar)
            m.evento.connect(on_evento)
            m.pagina_mudou.connect(self._fechar)   # fecha viewer ao paginar/trocar layout
            self.murais.append(m)
            self.tabs.addTab(m, f"{nome}  ·  {len(cams)}")
        self.tabs.currentChanged.connect(self._trocar)
        self.stack.addWidget(self.tabs)
        self.stack.addWidget(self._viewer())

    def _viewer(self):
        w = QWidget(); lay = QVBoxLayout(w); lay.setContentsMargins(16, 12, 16, 16)
        bar = QHBoxLayout()
        voltar = QPushButton("‹ Voltar ao mural")
        voltar.setObjectName("primary")
        voltar.setTooltip("Esc")
        voltar.clicked.connect(self._fechar)
        self.v_nome = QLabel("")
        self.v_nome.setObjectName("camName")
        self.v_nome.setStyleSheet("font-size:16px; font-weight:800; color:#ffffff;")
        bar.addWidget(voltar); bar.addSpacing(16); bar.addWidget(self.v_nome, 1)
        self.v_chips = QLabel("")
        self.v_chips.setObjectName("detChips")
        bar.addWidget(self.v_chips)
        lay.addLayout(bar)
        self.v_video = QLabel("")
        self.v_video.setAlignment(Qt.AlignCenter)
        self.v_video.setStyleSheet("background:#000; border-radius:8px;")
        lay.addWidget(self.v_video, 1)
        return w

    def ativar(self):
        self._trocar(self.tabs.currentIndex())

    def _trocar(self, idx):
        self._fechar()                 # sai do viewer ao trocar de categoria
        for i, m in enumerate(self.murais):
            m.iniciar() if i == idx else m.parar()

    def reiniciar_ativo(self):
        """Reinicia as threads do mural visível (p/ aplicar detector novo)."""
        idx = self.tabs.currentIndex()
        if 0 <= idx < len(self.murais):
            self.murais[idx].reiniciar()

    def _ampliar(self, card):
        if self._ampliado is not None:
            self._ampliado.mirror = None
        self._ampliado = card
        self.v_nome.setText(card.cam["nome"]); self.v_chips.setText(card.chips.text())
        card.mirror = (self.v_video, self.v_chips)
        self.stack.setCurrentIndex(1)

    def _fechar(self):
        if self._ampliado is not None:
            self._ampliado.mirror = None; self._ampliado = None
        self.stack.setCurrentIndex(0)

    def parar_tudo(self):
        for m in self.murais:
            m.parar()


class EventosSection(QWidget):
    """Log em tempo real das detecções — com empty state."""

    def __init__(self):
        super().__init__()
        lay = QVBoxLayout(self); lay.setContentsMargins(16, 12, 16, 16)

        top = QHBoxLayout()
        title = QLabel("Eventos de detecção")
        title.setObjectName("sectionTitle")
        top.addWidget(title)
        sub = QLabel("(tempo real)")
        sub.setObjectName("sectionSub")
        top.addWidget(sub)
        top.addStretch(1)

        self.btn_exportar = QPushButton("📥 Exportar evidência")
        self.btn_exportar.setTooltip("Empacota evidência em ZIP com hash SHA-256")
        self.btn_exportar.clicked.connect(self._exportar)
        top.addWidget(self.btn_exportar)

        limpar = QPushButton("🗑 Limpar")
        limpar.setTooltip("Limpa a tabela de eventos")
        limpar.clicked.connect(self._limpar)
        top.addWidget(limpar)
        lay.addLayout(top)

        self.empty_label = QLabel("Nenhum evento registrado ainda.\nAs detecções aparecerão aqui em tempo real.")
        self.empty_label.setAlignment(Qt.AlignCenter)
        self.empty_label.setStyleSheet(f"color:{theme.MUTED}; font-size:13px; padding:40px;")
        lay.addWidget(self.empty_label)

        self.tabela = QTableWidget(0, 3)
        self.tabela.setHorizontalHeaderLabels(["Horário", "Câmera", "Objetos"])
        self.tabela.horizontalHeader().setSectionResizeMode(2, QHeaderView.Stretch)
        self.tabela.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeToContents)
        self.tabela.verticalHeader().setVisible(False)
        self.tabela.setEditTriggers(QTableWidget.NoEditTriggers)
        self.tabela.setTooltip("Eventos de detecção registrados")
        self.tabela.hide()
        lay.addWidget(self.tabela)

    def registrar(self, hora, camera, texto):
        self.empty_label.hide()
        self.tabela.show()
        self.tabela.insertRow(0)
        self.tabela.setItem(0, 0, QTableWidgetItem(hora))
        self.tabela.setItem(0, 1, QTableWidgetItem(camera))
        self.tabela.setItem(0, 2, QTableWidgetItem(texto))
        while self.tabela.rowCount() > 300:
            self.tabela.removeRow(self.tabela.rowCount() - 1)

    def _limpar(self):
        self.tabela.setRowCount(0)
        self.tabela.hide()
        self.empty_label.show()

    def _exportar(self):
        caminho, _ = QFileDialog.getOpenFileName(
            self, "Selecionar arquivo de evidência", servicos.DIR_GRAVACOES,
            "Vídeos/Imagens (*.mp4 *.avi *.png *.jpg);;Todos (*)")
        if not caminho:
            return
        camera, ok = QInputDialog.getText(self, "Câmera", "Nome da câmera:")
        if not ok or not camera.strip():
            return
        descricao, ok = QInputDialog.getText(self, "Descrição", "Descrição da evidência:")
        if not ok:
            return
        resultado = servicos.exportar_evidencia(caminho, camera.strip(), descricao)
        if resultado:
            QMessageBox.information(self, "Exportação",
                                   f"Evidência exportada:\n{resultado}")
        else:
            QMessageBox.warning(self, "Erro", "Falha ao exportar evidência.")


VEICULOS = {"car", "truck", "bus", "motorcycle", "bicycle", "train"}


class Sparkline(QWidget):
    """Mini-gráfico de área (série temporal) desenhado com QPainter."""

    def __init__(self, cor=theme.ACCENT):
        super().__init__()
        self.cor = QColor(cor)
        self.dados = []
        self.setMinimumHeight(90)

    def set_dados(self, dados):
        self.dados = list(dados)
        self.update()

    def paintEvent(self, _):
        p = QPainter(self); p.setRenderHint(QPainter.Antialiasing)
        w, h = self.width(), self.height()
        p.fillRect(self.rect(), QColor(theme.CARD))
        if len(self.dados) < 2:
            return
        mx = max(self.dados) or 1
        n = len(self.dados)
        pts = [QPointF(i * w / (n - 1), h - 6 - (v / mx) * (h - 16))
               for i, v in enumerate(self.dados)]
        # área preenchida
        poly = QPolygonF([QPointF(0, h)] + pts + [QPointF(w, h)])
        grad = QLinearGradient(0, 0, 0, h)
        c = QColor(self.cor); c.setAlpha(90); grad.setColorAt(0, c)
        c2 = QColor(self.cor); c2.setAlpha(10); grad.setColorAt(1, c2)
        p.setBrush(QBrush(grad)); p.setPen(Qt.NoPen); p.drawPolygon(poly)
        # linha
        p.setBrush(Qt.NoBrush); p.setPen(QPen(self.cor, 2))
        p.drawPolyline(QPolygonF(pts))


class KpiCard(QFrame):
    """KPI card com borda accent superior e ícone."""

    def __init__(self, titulo, cor=None, icono=""):
        super().__init__()
        # Escolhe o objectName baseado na cor para o QSS
        if cor == theme.OK:
            self.setObjectName("kpiCardOk")
        elif cor == theme.ACCENT_2:
            self.setObjectName("kpiCardAccent2")
        elif cor == theme.DANGER:
            self.setObjectName("kpiCardDanger")
        else:
            self.setObjectName("kpiCard")
        v = QVBoxLayout(self); v.setSpacing(2); v.setContentsMargins(12, 10, 12, 8)

        header = QHBoxLayout()
        if icono:
            ico = QLabel(icono)
            ico.setStyleSheet("font-size:16px;")
            header.addWidget(ico)
        self.tit = QLabel(titulo)
        self.tit.setStyleSheet(f"color:{theme.MUTED}; font-size:10px; font-weight:600; letter-spacing:0.3px;")
        header.addWidget(self.tit)
        header.addStretch()
        v.addLayout(header)

        self.valor = QLabel("—")
        self.valor.setStyleSheet(
            f"color:{cor or theme.ACCENT}; font-size:28px; font-weight:800;")
        v.addWidget(self.valor)

        self.delta = QLabel("")
        self.delta.setStyleSheet(f"color:{theme.MUTED}; font-size:10px;")
        v.addWidget(self.delta)

    def set(self, valor, sub=""):
        self.valor.setText(str(valor)); self.delta.setText(sub)


class DashboardSection(QWidget):
    """Dashboard de negócio: KPIs, fluxo no tempo e ranking de câmeras."""

    def __init__(self):
        super().__init__()
        lay = QVBoxLayout(self); lay.setContentsMargins(24, 18, 24, 18); lay.setSpacing(14)

        title = QLabel("Dashboard operacional")
        title.setObjectName("sectionTitle")
        lay.addWidget(title)

        # linha 1 de KPIs
        l1 = QHBoxLayout()
        self.k_online = KpiCard("Câmeras online", theme.OK, "📹")
        self.k_uptime = KpiCard("Disponibilidade", theme.OK, "📊")
        self.k_agora = KpiCard("Objetos no quadro", theme.ACCENT, "🎯")
        self.k_pico = KpiCard("Pico na sessão", theme.ACCENT_2, "📈")
        for k in (self.k_online, self.k_uptime, self.k_agora, self.k_pico):
            l1.addWidget(k)
        lay.addLayout(l1)

        # linha 2 de KPIs
        l2 = QHBoxLayout()
        self.k_veic = KpiCard("Veículos", theme.ACCENT, "🚗")
        self.k_pess = KpiCard("Pessoas", theme.ACCENT_2, "👤")
        self.k_fluxo = KpiCard("Fluxo médio", theme.ACCENT, "⚡")
        self.k_eventos = KpiCard("Eventos", theme.MUTED, "📋")
        for k in (self.k_veic, self.k_pess, self.k_fluxo, self.k_eventos):
            l2.addWidget(k)
        lay.addLayout(l2)

        # fluxo no tempo
        fluxo_label = QLabel("Fluxo de objetos — últimos 90s")
        fluxo_label.setStyleSheet(f"color:{theme.MUTED}; font-size:11px; font-weight:600; padding-top:8px;")
        lay.addWidget(fluxo_label)
        self.spark = Sparkline(); lay.addWidget(self.spark)

        # ranking + barras
        bottom = QHBoxLayout()

        col_a = QVBoxLayout()
        rank_label = QLabel("Câmeras mais movimentadas")
        rank_label.setStyleSheet(f"color:{theme.MUTED}; font-size:11px; font-weight:600; padding-top:8px;")
        col_a.addWidget(rank_label)
        self.ranking = QTableWidget(0, 2)
        self.ranking.setHorizontalHeaderLabels(["Câmera", "Objetos"])
        self.ranking.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
        self.ranking.verticalHeader().setVisible(False)
        self.ranking.setEditTriggers(QTableWidget.NoEditTriggers)
        self.ranking.setTooltip("Top 6 câmeras com mais detecções")
        col_a.addWidget(self.ranking)

        col_b = QVBoxLayout()
        classes_label = QLabel("Objetos por classe (ao vivo)")
        classes_label.setStyleSheet(f"color:{theme.MUTED}; font-size:11px; font-weight:600; padding-top:8px;")
        col_b.addWidget(classes_label)
        self.barras_box = QVBoxLayout(); col_b.addLayout(self.barras_box); col_b.addStretch(1)

        bottom.addLayout(col_a, 1); bottom.addLayout(col_b, 1)
        lay.addLayout(bottom)
        self.barras = {}

    def atualizar(self, m):
        self.k_online.set(f"{m['online']}/{m['total']}")
        self.k_uptime.set(f"{m['uptime']:.0f}%")
        self.k_agora.set(m['agora'], f"{m['classes']} classes")
        self.k_pico.set(m['pico'])
        self.k_veic.set(m['veiculos'])
        self.k_pess.set(m['pessoas'])
        self.k_fluxo.set(f"{m['fluxo']:.1f}")
        self.k_eventos.set(m['eventos'])
        self.spark.set_dados(m['serie'])

        # ranking
        rank = sorted(m['por_camera'].items(), key=lambda x: -x[1])[:6]
        self.ranking.setRowCount(len(rank))
        for r, (nome, qtd) in enumerate(rank):
            self.ranking.setItem(r, 0, QTableWidgetItem(nome))
            self.ranking.setItem(r, 1, QTableWidgetItem(str(qtd)))

        # barras por classe
        agreg = m['agregado']
        maxv = max(agreg.values()) if agreg else 1
        for classe in list(self.barras):
            if classe not in agreg:
                self.barras.pop(classe).setParent(None)
        for classe, qtd in sorted(agreg.items(), key=lambda x: -x[1]):
            if classe not in self.barras:
                linha = QWidget(); h = QHBoxLayout(linha); h.setContentsMargins(0, 0, 0, 0)
                rot = QLabel(classe); rot.setFixedWidth(90)
                bar = QProgressBar(); bar.setTextVisible(True)
                bar.setStyleSheet(
                    f"QProgressBar{{background:{theme.CARD};border:1px solid {theme.BORDER};"
                    f"border-radius:6px;height:18px;color:{theme.TEXT};}}"
                    f"QProgressBar::chunk{{background:{theme.ACCENT};border-radius:6px;}}")
                h.addWidget(rot); h.addWidget(bar, 1)
                linha._bar = bar; self.barras[classe] = linha
                self.barras_box.addWidget(linha)
            b = self.barras[classe]._bar
            b.setMaximum(maxv); b.setValue(qtd); b.setFormat(f"{qtd}")


class CamerasSection(QWidget):
    """Gestão da lista de câmeras — com empty state."""

    alterado = Signal()

    def __init__(self, cameras):
        super().__init__()
        self.cameras = cameras
        lay = QVBoxLayout(self); lay.setContentsMargins(16, 12, 16, 16)

        title = QLabel("Gestão de câmeras")
        title.setObjectName("sectionTitle")
        lay.addWidget(title)

        self.empty_label = QLabel("Nenhuma câmera cadastrada.\nAdicione câmeras usando o formulário abaixo.")
        self.empty_label.setAlignment(Qt.AlignCenter)
        self.empty_label.setStyleSheet(f"color:{theme.MUTED}; font-size:13px; padding:40px;")
        lay.addWidget(self.empty_label)

        self.tabela = QTableWidget(0, 4)
        self.tabela.setHorizontalHeaderLabels(["Nome", "Categoria", "Tipo", "URL"])
        self.tabela.horizontalHeader().setSectionResizeMode(3, QHeaderView.Stretch)
        self.tabela.verticalHeader().setVisible(False)
        self.tabela.setEditTriggers(QTableWidget.NoEditTriggers)
        self.tabela.setTooltip("Lista de câmeras cadastradas")
        self.tabela.hide()
        lay.addWidget(self.tabela)

        form = QHBoxLayout()
        form.setSpacing(8)
        self.in_nome = QLineEdit(); self.in_nome.setPlaceholderText("Nome")
        self.in_nome.setTooltip("Nome descritivo da câmera")
        self.in_cat = QLineEdit(); self.in_cat.setPlaceholderText("Categoria")
        self.in_cat.setTooltip("Grupo/categoria (ex: Entrada, Estacionamento)")
        self.in_url = QLineEdit(); self.in_url.setPlaceholderText("rtsp:// ou .m3u8")
        self.in_url.setTooltip("URL RTSP (rtsp://...) ou HLS (http...m3u8)")
        add = QPushButton("＋ Adicionar")
        add.setObjectName("primary")
        add.setTooltip("Adiciona a câmera à lista")
        add.clicked.connect(self._add)
        rem = QPushButton("✕ Remover")
        rem.setObjectName("danger")
        rem.setTooltip("Remove a câmera selecionada")
        rem.clicked.connect(self._rem)
        form.addWidget(self.in_nome); form.addWidget(self.in_cat)
        form.addWidget(self.in_url, 1); form.addWidget(add); form.addWidget(rem)
        lay.addLayout(form)

        aviso = QLabel("As mudanças são salvas automaticamente. Reinicie o app para atualizar o mural.")
        aviso.setStyleSheet(f"color:{theme.MUTED}; font-size:10px; font-style:italic;")
        lay.addWidget(aviso)
        lay.addStretch()
        self._refresh()

    def _refresh(self):
        self.tabela.setRowCount(0)
        if not self.cameras:
            self.tabela.hide()
            self.empty_label.show()
            return
        self.empty_label.hide()
        self.tabela.show()
        for c in self.cameras:
            r = self.tabela.rowCount(); self.tabela.insertRow(r)
            self.tabela.setItem(r, 0, QTableWidgetItem(c["nome"]))
            self.tabela.setItem(r, 1, QTableWidgetItem(c.get("categoria", "")))
            self.tabela.setItem(r, 2, QTableWidgetItem(c.get("tipo", "")))
            self.tabela.setItem(r, 3, QTableWidgetItem(c["url"]))

    def _add(self):
        url = self.in_url.text().strip()
        if not validar_url(url):
            QMessageBox.warning(
                self, "URL inválida",
                "Informe uma URL RTSP (rtsp://…) ou HLS (http(s)://….m3u8) "
                "com host válido.")
            return
        if any(c["url"].lower() == url.lower() for c in self.cameras):
            QMessageBox.information(self, "Duplicada",
                                    "Essa câmera (URL) já está na lista.")
            return
        self.cameras.append({
            "nome": self.in_nome.text().strip() or url,
            "categoria": self.in_cat.text().strip() or "Outras",
            "tipo": "rtsp" if url.lower().startswith("rtsp") else "hls",
            "url": url,
        })
        salvar_cameras(self.cameras)
        self.in_nome.clear(); self.in_cat.clear(); self.in_url.clear()
        self._refresh(); self.alterado.emit()

    def _rem(self):
        r = self.tabela.currentRow()
        if r < 0:
            return
        del self.cameras[r]
        salvar_cameras(self.cameras)
        self._refresh(); self.alterado.emit()


class ConfigSection(QWidget):
    """Ajustes de performance / IA -> config.json."""

    def __init__(self, cfg):
        super().__init__()
        self.cfg = cfg
        lay = QVBoxLayout(self); lay.setContentsMargins(24, 20, 24, 20)

        title = QLabel("Configurações")
        title.setObjectName("sectionTitle")
        lay.addWidget(title)

        scroll = QScrollArea(); scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.NoFrame)
        conteudo = QWidget()
        cl = QVBoxLayout(conteudo); cl.setContentsMargins(0, 0, 0, 0)

        # Performance
        perf_title = QLabel("Performance e IA")
        perf_title.setStyleSheet(f"color:{theme.ACCENT}; font-size:13px; font-weight:700; padding-top:12px;")
        cl.addWidget(perf_title)

        form = QFormLayout()
        form.setSpacing(10)
        self.sp_skip = QSpinBox(); self.sp_skip.setRange(1, 30); self.sp_skip.setValue(cfg["detectar_a_cada"])
        self.sp_skip.setTooltip("Executar detecção a cada N frames (menor = mais IA)")
        self.sp_imgsz = QComboBox(); self.sp_imgsz.addItems(["320", "416", "480", "576", "640"])
        self.sp_imgsz.setCurrentText(str(cfg["imgsz"]))
        self.sp_imgsz.setTooltip("Resolução de inferência (maior = mais preciso, mais lento)")
        self.sp_conf = QSpinBox(); self.sp_conf.setRange(10, 90); self.sp_conf.setSuffix(" %")
        self.sp_conf.setValue(int(cfg["confianca"] * 100))
        self.sp_conf.setTooltip("Confiança mínima para considerar uma detecção")
        self.sp_fps = QSpinBox(); self.sp_fps.setRange(1, 60); self.sp_fps.setValue(cfg["fps_max"])
        self.sp_fps.setTooltip("Limite de frames por segundo por câmera")
        self.sp_col = QSpinBox(); self.sp_col.setRange(1, 4); self.sp_col.setValue(cfg["colunas"])
        self.sp_col.setTooltip("Número de colunas no mural de câmeras")
        form.addRow("Detectar a cada N frames:", self.sp_skip)
        form.addRow("Resolução de inferência (imgsz):", self.sp_imgsz)
        form.addRow("Confiança mínima:", self.sp_conf)
        form.addRow("FPS máximo por câmera:", self.sp_fps)
        form.addRow("Colunas do mural:", self.sp_col)
        cl.addLayout(form)

        # Privacy Masking
        priv_title = QLabel("Privacy Masking")
        priv_title.setStyleSheet(f"color:{theme.ACCENT}; font-size:13px; font-weight:700; padding-top:16px;")
        cl.addWidget(priv_title)
        priv_sub = QLabel("Zonas de exclusão onde pessoas são pixeladas automaticamente.")
        priv_sub.setStyleSheet(f"color:{theme.MUTED}; font-size:11px;")
        cl.addWidget(priv_sub)

        masks = cfg.get("privacy_masks", {})
        self.mask_table = QTableWidget(len(masks) or 0, 2)
        self.mask_table.setHorizontalHeaderLabels(["Câmera (URL)", "Polígono (JSON)"])
        self.mask_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.Stretch)
        self.mask_table.setTooltip("Polígonos de privacidade definidos")
        for r, (url, zona) in enumerate(masks.items()):
            self.mask_table.setItem(r, 0, QTableWidgetItem(url))
            self.mask_table.setItem(r, 1, QTableWidgetItem(json.dumps(zona)))
        cl.addWidget(self.mask_table)

        mask_bar = QHBoxLayout()
        mask_bar.setSpacing(8)
        self.in_mask_url = QLineEdit(); self.in_mask_url.setPlaceholderText("URL da câmera")
        self.in_mask_url.setTooltip("URL exata da câmera para aplicar a máscara")
        self.in_mask_pontos = QLineEdit()
        self.in_mask_pontos.setPlaceholderText("[[0.1,0.1],[0.9,0.1],[0.9,0.9],[0.1,0.9]]")
        self.in_mask_pontos.setTooltip("Coordenadas proporcionais (0.0-1.0) dos vértices do polígono")
        btn_add_mask = QPushButton("＋ Adicionar zona")
        btn_add_mask.setTooltip("Adiciona zona de exclusão")
        btn_add_mask.clicked.connect(self._add_mask)
        btn_rem_mask = QPushButton("✕ Remover")
        btn_rem_mask.setObjectName("danger")
        btn_rem_mask.setTooltip("Remove a zona selecionada")
        btn_rem_mask.clicked.connect(self._rem_mask)
        mask_bar.addWidget(self.in_mask_url); mask_bar.addWidget(self.in_mask_pontos, 1)
        mask_bar.addWidget(btn_add_mask); mask_bar.addWidget(btn_rem_mask)
        cl.addLayout(mask_bar)
        cl.addStretch(1)
        scroll.setWidget(conteudo)
        lay.addWidget(scroll, 1)

        salvar = QPushButton("💾 Salvar configurações")
        salvar.setObjectName("primary")
        salvar.setTooltip("Salva as configurações (reinício necessário)")
        salvar.clicked.connect(self._salvar)
        lay.addWidget(salvar, alignment=Qt.AlignLeft)

    def _add_mask(self):
        url = self.in_mask_url.text().strip()
        try:
            pontos = json.loads(self.in_mask_pontos.text())
        except json.JSONDecodeError:
            QMessageBox.warning(self, "Erro", "JSON inválido para polígono.")
            return
        if not isinstance(pontos, list) or len(pontos) < 3:
            QMessageBox.warning(self, "Erro", "Polígono precisa de pelo menos 3 pontos.")
            return
        masks = self.cfg.get("privacy_masks", {})
        masks[url] = pontos
        self.cfg["privacy_masks"] = masks
        r = self.mask_table.rowCount(); self.mask_table.insertRow(r)
        self.mask_table.setItem(r, 0, QTableWidgetItem(url))
        self.mask_table.setItem(r, 1, QTableWidgetItem(json.dumps(pontos)))
        self.in_mask_url.clear(); self.in_mask_pontos.clear()

    def _rem_mask(self):
        r = self.mask_table.currentRow()
        if r < 0:
            return
        url_item = self.mask_table.item(r, 0)
        if url_item:
            masks = self.cfg.get("privacy_masks", {})
            masks.pop(url_item.text(), None)
            self.cfg["privacy_masks"] = masks
        self.mask_table.removeRow(r)

    def _salvar(self):
        self.cfg.update({
            "detectar_a_cada": self.sp_skip.value(),
            "imgsz": int(self.sp_imgsz.currentText()),
            "confianca": self.sp_conf.value() / 100.0,
            "fps_max": self.sp_fps.value(),
            "colunas": self.sp_col.value(),
        })
        salvar_config(self.cfg)
        QMessageBox.information(self, "Configurações",
                               "Salvo em config.json.\nReinicie o app para aplicar.")


# ====================================================================
# Janela principal
# ====================================================================
class Janela(QMainWindow):
    def __init__(self, ia_inicial=True, usuario=None):
        super().__init__()
        self.setWindowTitle("vigia-cam")
        self.resize(1280, 840)
        self.usuario = usuario or {"perfil": "admin"}
        self.cameras = carregar_cameras()
        self.cameras = [c for c in self.cameras
                        if servicos.usuario_pode_acessar(self.usuario, c["url"])]
        self.grupos = agrupar_por_categoria(self.cameras)
        self.detector = None
        self._ia_inicial = ia_inicial
        self._latest = {}                    # nome -> (contagem, online, t)
        self._ult_evento = defaultdict(float)
        # métricas de sessão
        self._serie = deque(maxlen=90)       # objetos/seg (sparkline)
        self._pico = 0
        self._eventos = 0
        self._up_soma = 0.0                  # acumula online/total p/ disponibilidade
        self._up_amostras = 0

        self._montar_ui()
        self.show()
        QApplication.processEvents()
        self._carregar_detector()
        self.sec_ao_vivo.ativar()

    def _montar_ui(self):
        root = QWidget(); root.setObjectName("root"); self.setCentralWidget(root)
        col = QVBoxLayout(root); col.setContentsMargins(0, 0, 0, 0); col.setSpacing(0)
        col.addWidget(self._header())

        perfil = self.usuario.get("perfil", "admin")
        self.nav = QTabWidget(); self.nav.setObjectName("nav"); self.nav.setDocumentMode(True)
        self.sec_ao_vivo = AoVivoSection(self.grupos, lambda: self.detector, self._on_evento)
        self.sec_eventos = EventosSection()
        self.sec_dash = DashboardSection()
        self.sec_cam = CamerasSection(self.cameras) if perfil == "admin" else None
        self.sec_cfg = ConfigSection(CFG) if perfil == "admin" else None
        self.nav.addTab(self.sec_ao_vivo, "  ● Ao Vivo  ")
        self.nav.addTab(self.sec_eventos, "  📋 Eventos  ")
        self.nav.addTab(self.sec_dash, "  📊 Dashboard  ")
        if self.sec_cam is not None:
            self.nav.addTab(self.sec_cam, "  📹 Câmeras  ")
        if self.sec_cfg is not None:
            self.nav.addTab(self.sec_cfg, "  ⚙ Configurações  ")
        col.addWidget(self.nav, 1)
        self.statusBar().showMessage(f"Conectado como {self.usuario.get('usuario', '?')} ({perfil})")

        self._timer = QTimer(self); self._timer.timeout.connect(self._tick); self._timer.start(1000)

    def _header(self):
        h = QFrame(); h.setObjectName("header"); h.setFixedHeight(64)
        lay = QHBoxLayout(h); lay.setContentsMargins(20, 0, 20, 0)
        marca = QHBoxLayout(); marca.setSpacing(0)
        logo = QLabel("VIGIA"); logo.setObjectName("logo")
        dot = QLabel("•CAM"); dot.setObjectName("logoDot")
        marca.addWidget(logo); marca.addWidget(dot)
        bloco = QVBoxLayout(); bloco.setSpacing(0); bloco.addLayout(marca)
        sub = QLabel("monitoramento ao vivo · detecção por IA"); sub.setObjectName("subtitle")
        bloco.addWidget(sub); lay.addLayout(bloco); lay.addStretch(1)

        self.chk_det = QCheckBox("Detecção IA")
        self.chk_det.setChecked(self._ia_inicial)
        self.chk_det.setTooltip("Ativa/desativa a detecção de objetos por IA")
        self.chk_det.stateChanged.connect(self._toggle_detector)
        lay.addWidget(self.chk_det)

        lay.addSpacing(12)

        self.user_label = QLabel(f"👤 {self.usuario.get('usuario', '?')}")
        self.user_label.setStyleSheet(
            f"color:{theme.MUTED}; font-size:11px; background:{theme.CARD}; "
            f"border:1px solid {theme.BORDER}; border-radius:6px; padding:4px 10px;")
        self.user_label.setTooltip(f"Perfil: {self.usuario.get('perfil', '?')}")
        lay.addWidget(self.user_label)

        self.clock = QLabel("")
        self.clock.setObjectName("clock")
        lay.addSpacing(12); lay.addWidget(self.clock)
        return h

    # ---------- detector ----------
    def _carregar_detector(self):
        if self.chk_det.isChecked() and Detector.disponivel():
            self.statusBar().showMessage("Carregando YOLOv8n (1o uso baixa os pesos)…")
            QApplication.processEvents()
            try:
                self.detector = Detector(conf=CFG["confianca"], imgsz=CFG["imgsz"],
                                         classes=CFG["classes"])
                dev = {"mps": "GPU Apple Silicon (MPS)", "cuda": "CUDA",
                       "cpu": "CPU"}.get(self.detector.device, self.detector.device)
                self.statusBar().showMessage(f"IA pronta · acelerador: {dev}")
            except Exception as e:  # noqa
                QMessageBox.warning(self, "Detector", f"Seguindo sem detecção:\n{e}")
                self.detector = None

    def _toggle_detector(self):
        if self.chk_det.isChecked():
            self._carregar_detector()
        else:
            self.detector = None
        # Bug 1: força reinício do mural ativo (ativar() não reinicia se já ativo)
        self.sec_ao_vivo.reiniciar_ativo()

    # ---------- eventos / agregação ----------
    @Slot(str, dict, bool)
    def _on_evento(self, camera, contagem, online):
        self._latest[camera] = (contagem, online, time.monotonic())
        if contagem and (time.monotonic() - self._ult_evento[camera] > 2.0):
            self._ult_evento[camera] = time.monotonic()
            self._eventos += 1
            texto = ", ".join(f"{k} ({v})" for k, v in contagem.items())
            self.sec_eventos.registrar(time.strftime("%H:%M:%S"), camera, texto)

    def _tick(self):
        self.clock.setText(time.strftime("%H:%M:%S"))
        agreg = defaultdict(int); por_camera = {}; online = 0
        agora = time.monotonic()
        for nome, (cont, on, t) in self._latest.items():
            if agora - t > 5:                # ativo = reportou há <5s
                continue
            if on:
                online += 1
            por_camera[nome] = sum(cont.values())
            for k, v in cont.items():
                agreg[k] += v

        total_obj = sum(agreg.values())
        self._serie.append(total_obj)
        self._pico = max(self._pico, total_obj)
        # Bug 4: só amostra disponibilidade quando há câmeras reportando,
        # senão o "conectando…" inicial puxa o KPI pra ~0%.
        if por_camera:
            self._up_soma += online / len(por_camera)
            self._up_amostras += 1
        veiculos = sum(v for k, v in agreg.items() if k in VEICULOS)
        pessoas = agreg.get("person", 0)
        fluxo = (sum(self._serie) / len(self._serie)) if self._serie else 0.0

        self.sec_dash.atualizar({
            "online": online, "total": len(self.cameras),
            "uptime": 100.0 * self._up_soma / max(1, self._up_amostras),
            "agora": total_obj, "classes": len(agreg), "pico": self._pico,
            "veiculos": veiculos, "pessoas": pessoas, "fluxo": fluxo,
            "eventos": self._eventos, "serie": self._serie,
            "por_camera": por_camera, "agregado": dict(agreg),
        })

    def closeEvent(self, event):
        self.sec_ao_vivo.parar_tudo()
        event.accept()


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
