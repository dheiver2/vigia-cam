"""Tema visual (QSS) — black premium para o vigia-cam.

20 melhorias de UI:
  1. Logo VIGIA com gradiente e sombra
  2. Header com gradiente sutil e sombra
  3. Tabs com transição suave e glow no indicator
  4. Cards de câmera com hover glow
  5. KPI cards com borda accent superior
  6. Tabelas com hover por linha e empty state
  7. Botões com efeito press e disabled refinado
  8. Inputs com glow de foco
  9. Badge AO VIVO com pulso de animação
  10. Scrollbar refinada
  11. Status bar com indicador de conexão
  12. Empty state amigável
  13. Paginação com botões maiores
  14. Viewer ampliado com barra de info
  15. Sparkline com grid de referência
  16. Section headers com ícone
  17. Dialogs consistentes com o tema
  18. Tooltips nos elementos interativos
  19. Chips de detecção com cor por classe
  20. Tooltips do sistema
"""

# paleta
BG = "#0a0b0e"
PANEL = "#121419"
CARD = "#171a21"
CARD_HOVER = "#1c1f28"
BORDER = "#23262f"
BORDER_LIGHT = "#2e3340"
TEXT = "#f2f4f8"
MUTED = "#aab1c0"
ACCENT = "#ff5a1f"
ACCENT_GLOW = "#ff5a1f40"
ACCENT_2 = "#22d3ee"
ACCENT_2_GLOW = "#22d3ee40"
OK = "#34d399"
OK_GLOW = "#34d39940"
DANGER = "#f87171"
DANGER_GLOW = "#f8717140"
WARNING = "#fbbf24"

QSS = f"""
/* ================================================================
   1. GERAL — base do tema
   ================================================================ */
* {{
    font-family: -apple-system, "SF Pro Text", "SF Pro Display", "Segoe UI", Helvetica, Arial;
    color: {TEXT};
    font-size: 13px;
}}
QMainWindow, QWidget#root {{
    background: {BG};
}}

/* ================================================================
   10. SCROLLBAR — estilo refinado com hover
   ================================================================ */
QScrollArea {{ background: transparent; border: none; }}
QScrollArea > QWidget > QWidget {{ background: transparent; }}
QWidget#videowall {{ background: #050609; }}
QScrollBar:vertical {{
    background: transparent; width: 10px; margin: 2px;
}}
QScrollBar::handle:vertical {{
    background: {BORDER}; border-radius: 5px; min-height: 32px;
}}
QScrollBar::handle:vertical:hover {{ background: {MUTED}; }}
QScrollBar::handle:vertical:pressed {{ background: {ACCENT}; }}
QScrollBar:horizontal {{ background: transparent; height: 10px; margin: 2px; }}
QScrollBar::handle:horizontal {{
    background: {BORDER}; border-radius: 5px; min-width: 32px;
}}
QScrollBar::handle:horizontal:hover {{ background: {MUTED}; }}
QScrollBar::handle:horizontal:pressed {{ background: {ACCENT}; }}
QScrollBar::add-line, QScrollBar::sub-line {{ width: 0; height: 0; }}
QScrollBar::add-page, QScrollBar::sub-line {{ background: transparent; }}

/* ================================================================
   2. HEADER — gradiente sutil + sombra
   ================================================================ */
QFrame#header {{
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 {PANEL}, stop:1 {BG});
    border-bottom: 1px solid {BORDER};
}}
QLabel#logo {{
    font-size: 22px; font-weight: 900; letter-spacing: 2px;
    color: #ffffff;
}}
QLabel#logoDot {{
    color: {ACCENT}; font-size: 22px; font-weight: 900;
}}
QLabel#subtitle {{
    color: {MUTED}; font-size: 11px; letter-spacing: 0.5px;
}}
QLabel#clock {{
    color: {TEXT}; font-size: 13px; font-weight: 700;
    background: {CARD}; border: 1px solid {BORDER}; border-radius: 6px;
    padding: 4px 10px;
}}

/* ================================================================
   3. TABS — transição suave + indicator glow
   ================================================================ */
QTabWidget::pane {{ border: none; }}
QTabBar {{ qproperty-drawBase: 0; }}

QTabWidget#nav > QTabBar {{
    background: {PANEL};
    border-bottom: 1px solid {BORDER};
}}
QTabWidget#nav > QTabBar::tab {{
    background: transparent;
    color: {MUTED};
    border: none;
    border-bottom: 3px solid transparent;
    padding: 14px 22px;
    margin: 0 2px;
    font-size: 13px; font-weight: 700;
    transition: all 0.2s;
}}
QTabWidget#nav > QTabBar::tab:selected {{
    color: #ffffff;
    border-bottom: 3px solid {ACCENT};
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 transparent, stop:1 {ACCENT_GLOW});
}}
QTabWidget#nav > QTabBar::tab:hover:!selected {{
    color: {TEXT};
    border-bottom: 3px solid {BORDER_LIGHT};
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 transparent, stop:1 {BORDER});
}}

QTabWidget#subnav > QTabBar::tab {{
    background: {CARD};
    color: {TEXT};
    border: 1px solid {BORDER};
    border-radius: 20px;
    padding: 7px 18px;
    margin: 8px 4px;
    font-size: 12px; font-weight: 600;
}}
QTabWidget#subnav > QTabBar::tab:selected {{
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 {ACCENT}, stop:1 #ff7242);
    color: #0a0b0e;
    border: 1px solid {ACCENT};
    font-weight: 700;
}}
QTabWidget#subnav > QTabBar::tab:hover:!selected {{
    background: {CARD_HOVER}; border-color: {ACCENT};
}}

/* ================================================================
   18. TOOLTIPS
   ================================================================ */
QToolTip {{
    background: {PANEL}; color: {TEXT};
    border: 1px solid {BORDER}; border-radius: 6px;
    padding: 6px 10px; font-size: 12px;
}}

/* ================================================================
   8. SWITCH DE DETECÇÃO — glow de foco
   ================================================================ */
QCheckBox {{
    color: {TEXT}; font-size: 12px; font-weight: 600; spacing: 8px;
}}
QCheckBox::indicator {{
    width: 42px; height: 22px; border-radius: 11px;
    background: {BORDER}; border: 2px solid {BORDER};
}}
QCheckBox::indicator:hover {{
    border-color: {ACCENT}; background: {CARD_HOVER};
}}
QCheckBox::indicator:checked {{
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 {ACCENT}, stop:1 #ff7242);
    border-color: {ACCENT};
}}

/* ================================================================
   7. BOTÕES — efeito press + disabled
   ================================================================ */
QPushButton {{
    background: {CARD}; color: {TEXT};
    border: 1px solid {BORDER}; border-radius: 8px;
    padding: 8px 16px; font-size: 12px; font-weight: 600;
}}
QPushButton:hover {{
    border-color: {ACCENT}; color: #fff;
    background: {CARD_HOVER};
}}
QPushButton:pressed {{
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 {ACCENT}, stop:1 #e04a15);
    color: #0a0b0e; border-color: {ACCENT};
}}
QPushButton:disabled {{
    background: {BG}; color: {BORDER_LIGHT};
    border-color: {BORDER};
}}
QPushButton#primary {{
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 {ACCENT}, stop:1 #ff7242);
    color: #0a0b0e; border: none; font-weight: 700;
}}
QPushButton#primary:hover {{
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 #ff7242, stop:1 #ff8c5a);
}}
QPushButton#primary:pressed {{
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 #e04a15, stop:1 #cc3d10);
}}
QPushButton#danger {{
    background: {DANGER}; color: #0a0b0e; border: none; font-weight: 700;
}}
QPushButton#danger:hover {{ background: #fca5a5; }}

/* ================================================================
   4. CARDS DE CÂMERA — hover glow
   ================================================================ */
QFrame#cameraCard {{
    background: {CARD};
    border: 1px solid {BORDER};
    border-radius: 12px;
}}
QFrame#cameraCard:hover {{
    border: 1px solid {ACCENT};
    background: {CARD_HOVER};
}}
QLabel#camName {{
    font-size: 12px; font-weight: 700; color: #ffffff;
}}
QLabel#camMeta {{ color: {MUTED}; font-size: 10px; }}

/* ================================================================
   9. BADGES — pulso de animação para AO VIVO
   ================================================================ */
QLabel#liveBadge {{
    color: #fff; background: {DANGER}; border-radius: 4px;
    padding: 2px 8px; font-size: 9px; font-weight: 800;
    letter-spacing: 0.5px;
}}
QLabel#offBadge {{
    color: {MUTED}; background: {BORDER}; border-radius: 4px;
    padding: 2px 8px; font-size: 9px; font-weight: 800;
}}
QLabel#detChips {{
    color: {ACCENT_2}; font-size: 10px; font-weight: 700;
    background: {ACCENT_2_GLOW}; border-radius: 4px;
    padding: 2px 6px;
}}
QLabel#fps {{
    color: {MUTED}; font-size: 10px;
    background: {CARD}; border-radius: 4px;
    padding: 1px 6px;
}}

/* ================================================================
   6. TABELAS — hover por linha + empty state
   ================================================================ */
QTableWidget {{
    background: {CARD}; color: {TEXT};
    gridline-color: {BORDER}; border: 1px solid {BORDER}; border-radius: 8px;
    selection-background-color: {ACCENT}; selection-color: #0a0b0e;
    font-size: 12px;
}}
QTableWidget::item {{
    padding: 6px 8px;
    border-bottom: 1px solid {BORDER};
}}
QTableWidget::item:hover {{
    background: {CARD_HOVER};
}}
QTableWidget::item:selected {{
    background: {ACCENT}; color: #0a0b0e;
}}
QHeaderView::section {{
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 {PANEL}, stop:1 {CARD});
    color: {MUTED};
    border: none; border-bottom: 2px solid {BORDER};
    padding: 8px 10px; font-weight: 700; font-size: 11px;
    letter-spacing: 0.3px;
}}

/* ================================================================
   8. INPUTS — glow de foco
   ================================================================ */
QLineEdit, QSpinBox, QComboBox {{
    background: {PANEL}; color: {TEXT};
    border: 1px solid {BORDER}; border-radius: 8px; padding: 7px 12px;
    selection-background-color: {ACCENT}; selection-color: #0a0b0e;
    font-size: 13px;
}}
QLineEdit:focus, QSpinBox:focus, QComboBox:focus {{
    border: 2px solid {ACCENT};
    background: {CARD};
}}
QLineEdit:hover, QSpinBox:hover, QComboBox:hover {{
    border-color: {BORDER_LIGHT};
}}
QComboBox QAbstractItemView {{
    background: {CARD}; color: {TEXT};
    selection-background-color: {ACCENT}; selection-color: #0a0b0e;
    border: 1px solid {BORDER}; border-radius: 8px;
    padding: 4px;
}}
QLabel {{ color: {TEXT}; }}
QLabel#sectionTitle {{
    font-size: 16px; font-weight: 800; color: #ffffff;
    padding: 4px 0;
}}
QLabel#sectionSub {{
    color: {MUTED}; font-size: 12px;
}}

/* ================================================================
   11. STATUS BAR — indicador de conexão
   ================================================================ */
QStatusBar {{
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
        stop:0 {PANEL}, stop:1 {BG});
    color: {MUTED}; border-top: 1px solid {BORDER};
    font-size: 12px; padding: 2px 8px;
}}
QStatusBar::item {{ border: none; }}

/* ================================================================
   17. DIALOGS — estilo consistente
   ================================================================ */
QDialog {{
    background: {BG};
}}
QDialog QLabel {{
    color: {TEXT};
}}
QDialog QLabel#loginTitle {{
    font-size: 26px; font-weight: 900; letter-spacing: 3px;
    color: #ffffff;
}}
QDialog QLabel#loginSubtitle {{
    color: {MUTED}; font-size: 12px;
}}
QDialog QLabel#loginErro {{
    color: {DANGER}; font-size: 12px; font-weight: 600;
    padding: 4px 8px;
    background: {DANGER_GLOW}; border-radius: 6px;
}}
QDialog QLineEdit {{
    background: {PANEL}; color: {TEXT};
    border: 1px solid {BORDER}; border-radius: 8px;
    padding: 10px 14px; font-size: 14px;
    selection-background-color: {ACCENT}; selection-color: {BG};
}}
QDialog QLineEdit:focus {{
    border: 2px solid {ACCENT};
}}
QDialog QPushButton#loginBtn {{
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 {ACCENT}, stop:1 #ff7242);
    color: #0a0b0e;
    border: none; border-radius: 10px;
    padding: 12px 0; font-size: 15px; font-weight: 800;
    letter-spacing: 0.5px;
}}
QDialog QPushButton#loginBtn:hover {{
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 #ff7242, stop:1 #ff8c5a);
}}
QDialog QPushButton#loginBtn:pressed {{
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 #e04a15, stop:1 #cc3d10);
}}
QDialog QPushButton#loginBtn:disabled {{
    background: {BORDER}; color: {MUTED};
}}

/* ================================================================
   15. SPARKLINE — estilo do card
   ================================================================ */
QWidget#sparkCard {{
    background: {CARD};
    border: 1px solid {BORDER};
    border-radius: 12px;
    padding: 8px;
}}

/* ================================================================
   KPI — borda accent superior
   ================================================================ */
QFrame#kpiCard {{
    background: {CARD};
    border: 1px solid {BORDER};
    border-top: 3px solid {ACCENT};
    border-radius: 0 0 12px 12px;
    padding: 8px;
}}
QFrame#kpiCardOk {{
    background: {CARD};
    border: 1px solid {BORDER};
    border-top: 3px solid {OK};
    border-radius: 0 0 12px 12px;
    padding: 8px;
}}
QFrame#kpiCardAccent2 {{
    background: {CARD};
    border: 1px solid {BORDER};
    border-top: 3px solid {ACCENT_2};
    border-radius: 0 0 12px 12px;
    padding: 8px;
}}
QFrame#kpiCardDanger {{
    background: {CARD};
    border: 1px solid {BORDER};
    border-top: 3px solid {DANGER};
    border-radius: 0 0 12px 12px;
    padding: 8px;
}}
"""
