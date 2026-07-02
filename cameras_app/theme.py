"""Tema visual (QSS) — black premium para o vigia-cam."""

# paleta
BG = "#0a0b0e"          # fundo geral
PANEL = "#121419"       # painéis
CARD = "#171a21"        # cards
BORDER = "#23262f"      # bordas
TEXT = "#f2f4f8"        # texto principal
MUTED = "#aab1c0"       # texto secundário (contraste >= 4.5:1 sobre o fundo)
ACCENT = "#ff5a1f"      # laranja de marca
ACCENT_2 = "#22d3ee"    # ciano (detecção)
OK = "#34d399"
DANGER = "#f87171"

QSS = f"""
* {{
    font-family: -apple-system, "SF Pro Text", "Segoe UI", Helvetica, Arial;
    color: {TEXT};
}}
QMainWindow, QWidget#root {{
    background: {BG};
}}

/* ---------- Header ---------- */
QFrame#header {{
    background: {PANEL};
    border-bottom: 1px solid {BORDER};
}}
QLabel#logo {{
    font-size: 20px; font-weight: 800; letter-spacing: 1px;
}}
QLabel#logoDot {{ color: {ACCENT}; font-size: 20px; font-weight: 800; }}
QLabel#subtitle {{ color: {MUTED}; font-size: 11px; }}
QLabel#clock {{ color: {MUTED}; font-size: 12px; font-weight: 600; }}

QTabWidget::pane {{ border: none; }}
QTabBar {{ qproperty-drawBase: 0; }}

/* ---------- Nav principal (funcionalidades) — sublinhado ---------- */
QTabWidget#nav > QTabBar {{ background: {PANEL}; }}
QTabWidget#nav > QTabBar::tab {{
    background: transparent;
    color: {MUTED};
    border: none;
    border-bottom: 2px solid transparent;
    padding: 12px 18px;
    margin: 0 2px;
    font-size: 13px; font-weight: 700;
}}
QTabWidget#nav > QTabBar::tab:selected {{
    color: #ffffff;
    border-bottom: 2px solid {ACCENT};
}}
QTabWidget#nav > QTabBar::tab:hover:!selected {{
    color: {TEXT};
    border-bottom: 2px solid {BORDER};
}}

/* ---------- Sub-abas (categorias) — pílulas ---------- */
QTabWidget#subnav > QTabBar::tab {{
    background: {CARD};
    color: {TEXT};
    border: 1px solid {BORDER};
    border-radius: 16px;
    padding: 6px 16px;
    margin: 8px 4px;
    font-size: 12px; font-weight: 600;
}}
QTabWidget#subnav > QTabBar::tab:selected {{
    background: {ACCENT};
    color: #0a0b0e;
    border: 1px solid {ACCENT};
}}
QTabWidget#subnav > QTabBar::tab:hover:!selected {{
    background: {PANEL}; border-color: {ACCENT};
}}

/* ---------- Switch de detecção ---------- */
QCheckBox {{ color: {TEXT}; font-size: 12px; font-weight: 600; spacing: 8px; }}
QCheckBox::indicator {{
    width: 40px; height: 20px; border-radius: 10px;
    background: {BORDER}; border: 1px solid {BORDER};
}}
QCheckBox::indicator:checked {{ background: {ACCENT}; border-color: {ACCENT}; }}

/* ---------- Botões ---------- */
QPushButton {{
    background: {CARD}; color: {TEXT};
    border: 1px solid {BORDER}; border-radius: 8px;
    padding: 7px 14px; font-size: 12px; font-weight: 600;
}}
QPushButton:hover {{ border-color: {ACCENT}; color: #fff; }}
QPushButton:pressed {{ background: {ACCENT}; color: #0a0b0e; }}
QPushButton#primary {{ background: {ACCENT}; color: #0a0b0e; border: none; }}
QPushButton#primary:hover {{ background: #ff7242; }}

/* ---------- Cards de câmera ---------- */
QFrame#cameraCard {{
    background: {CARD};
    border: 1px solid {BORDER};
    border-radius: 12px;
}}
QFrame#cameraCard:hover {{ border: 1px solid {ACCENT}; }}
QLabel#camName {{ font-size: 12px; font-weight: 700; }}
QLabel#camMeta {{ color: {MUTED}; font-size: 10px; }}
QLabel#liveBadge {{
    color: #fff; background: {DANGER}; border-radius: 4px;
    padding: 1px 6px; font-size: 9px; font-weight: 800;
}}
QLabel#offBadge {{
    color: {MUTED}; background: {BORDER}; border-radius: 4px;
    padding: 1px 6px; font-size: 9px; font-weight: 800;
}}
QLabel#detChips {{ color: {ACCENT_2}; font-size: 10px; font-weight: 700; }}
QLabel#fps {{ color: {MUTED}; font-size: 10px; }}

/* ---------- Tabelas ---------- */
QTableWidget {{
    background: {CARD}; color: {TEXT};
    gridline-color: {BORDER}; border: 1px solid {BORDER}; border-radius: 8px;
    selection-background-color: {ACCENT}; selection-color: #0a0b0e;
}}
QHeaderView::section {{
    background: {PANEL}; color: {MUTED};
    border: none; border-bottom: 1px solid {BORDER};
    padding: 6px 8px; font-weight: 700; font-size: 11px;
}}
QTableWidget::item {{ padding: 4px 6px; }}

/* ---------- Inputs ---------- */
QLineEdit, QSpinBox, QComboBox {{
    background: {CARD}; color: {TEXT};
    border: 1px solid {BORDER}; border-radius: 6px; padding: 5px 8px;
    selection-background-color: {ACCENT}; selection-color: #0a0b0e;
}}
QLineEdit:focus, QSpinBox:focus, QComboBox:focus {{ border-color: {ACCENT}; }}
QComboBox QAbstractItemView {{
    background: {CARD}; color: {TEXT};
    selection-background-color: {ACCENT}; selection-color: #0a0b0e;
}}
QLabel {{ color: {TEXT}; }}

QStatusBar {{ background: {PANEL}; color: {MUTED}; border-top: 1px solid {BORDER}; }}
QStatusBar::item {{ border: none; }}
"""
