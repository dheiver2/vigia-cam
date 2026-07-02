"""Testes das funções puras de app.py (validação de config/URL/câmeras).

Não instanciam PySide6/QApplication — cobrem só a lógica de dados, que é
onde entradas externas (config.json, cameras.json, URLs digitadas) chegam.
"""

import app


def test_validar_config_aceita_padrao_quando_vazio():
    cfg = app.validar_config({})
    assert cfg == app.CFG_PADRAO


def test_validar_config_clampa_fora_da_faixa():
    cfg = app.validar_config({"fps_max": 999, "confianca": -1})
    assert cfg["fps_max"] == app.CFG_LIMITES["fps_max"][1]
    assert cfg["confianca"] == app.CFG_LIMITES["confianca"][0]


def test_validar_config_ignora_tipo_errado():
    cfg = app.validar_config({"fps_max": "rapido", "colunas": True})
    assert cfg["fps_max"] == app.CFG_PADRAO["fps_max"]
    assert cfg["colunas"] == app.CFG_PADRAO["colunas"]


def test_validar_config_imgsz_multiplo_de_32():
    cfg = app.validar_config({"imgsz": 500})
    assert cfg["imgsz"] % 32 == 0


def test_validar_config_nao_e_dict_retorna_padrao():
    assert app.validar_config(None) == app.CFG_PADRAO
    assert app.validar_config("bagunca") == app.CFG_PADRAO


def test_validar_url_aceita_rtsp_e_hls():
    assert app.validar_url("rtsp://exemplo.com/stream")
    assert app.validar_url("https://exemplo.com/live/a.m3u8")


def test_validar_url_rejeita_esquemas_perigosos():
    assert not app.validar_url("file:///etc/passwd")
    assert not app.validar_url("javascript:alert(1)")
    assert not app.validar_url("")


def test_validar_url_http_sem_m3u8_rejeitado():
    assert not app.validar_url("http://exemplo.com/pagina.html")


def test_validar_url_sem_host_rejeitado():
    assert not app.validar_url("rtsp:///stream")


def test_normalizar_camera_valida():
    cam = app._normalizar_camera({
        "nome": "Cam 1", "url": "rtsp://exemplo.com/s", "categoria": "Teste",
    })
    assert cam == {
        "nome": "Cam 1", "categoria": "Teste", "tipo": "rtsp",
        "url": "rtsp://exemplo.com/s",
    }


def test_normalizar_camera_url_invalida_retorna_none():
    assert app._normalizar_camera({"nome": "X", "url": "not-a-url"}) is None


def test_normalizar_camera_usa_url_como_nome_padrao():
    cam = app._normalizar_camera({"url": "https://exemplo.com/a.m3u8"})
    assert cam["nome"] == "https://exemplo.com/a.m3u8"
    assert cam["categoria"] == "Outras"
    assert cam["tipo"] == "hls"


def test_agrupar_por_categoria():
    cams = [
        {"categoria": "A", "nome": "1"},
        {"categoria": "B", "nome": "2"},
        {"categoria": "A", "nome": "3"},
    ]
    grupos = app.agrupar_por_categoria(cams)
    assert list(grupos.keys()) == ["A", "B"]
    assert len(grupos["A"]) == 2
    assert len(grupos["B"]) == 1


def test_salvar_e_carregar_config_roundtrip(tmp_path, monkeypatch):
    caminho = tmp_path / "config.json"
    monkeypatch.setattr(app, "CONFIG_JSON", str(caminho))
    cfg = app.validar_config({"fps_max": 15})
    app.salvar_config(cfg)
    assert caminho.exists()
    recarregado = app.carregar_config()
    assert recarregado["fps_max"] == 15


def test_salvar_e_carregar_cameras_roundtrip(tmp_path, monkeypatch):
    caminho = tmp_path / "cameras.json"
    monkeypatch.setattr(app, "CAMERAS_JSON", str(caminho))
    cams = [{"nome": "Cam", "categoria": "X", "tipo": "rtsp", "url": "rtsp://a.com/s"}]
    app.salvar_cameras(cams)
    assert app.carregar_cameras() == cams
