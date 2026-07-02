# vigia-cam

![CI](https://github.com/dheiver2/vigia-cam/actions/workflows/ci.yml/badge.svg)
![Python](https://img.shields.io/badge/python-3.9%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

App desktop (Python + PySide6/Qt + OpenCV) para monitoramento ao vivo de
câmeras **RTSP** e **HLS (`.m3u8`)** com **detecção de objetos em tempo real**
via **YOLOv8n** (ultralytics).

## Funcionalidades

Navegação por abas, no estilo de um VMS (video management system):

| Aba | O que faz |
|---|---|
| **Ao Vivo** | Mural de câmeras por categoria, paginado; clique num card para ampliar |
| **Eventos** | Log em tempo real das detecções (horário, câmera, objetos) |
| **Dashboard** | KPIs agregados: câmeras online, disponibilidade, fluxo, ranking |
| **Câmeras** | Gestão da lista (adicionar/remover) → `cameras.json` |
| **Configurações** | Ajustes de performance/IA (FPS, resolução, confiança) → `config.json` |

Só o mural da categoria/página **visível** roda threads de captura — o custo
de CPU não cresce com o total de câmeras cadastradas, só com o layout ativo.

O modelo YOLOv8n ("nano") roda em CPU (ou GPU Apple Silicon via MPS / CUDA,
quando disponíveis) e baixa os pesos (~6 MB) automaticamente no primeiro uso.

## ⚠️ Uso responsável

Use apenas com streams que você tem autorização para acessar:
- Câmeras oficiais de trânsito (HLS/`.m3u8` publicados por órgãos públicos —
  as incluídas em `cameras.json` são feeds públicos do Seattle DOT)
- Streams de teste públicos
- Suas próprias câmeras IP

Acessar câmeras de terceiros sem autorização é invasão de privacidade e pode
configurar crime (LGPD + art. 154-A do Código Penal).

## Como rodar

```bash
./run.sh
```

Ou manualmente:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python cameras_app/app.py
```

### Opções de linha de comando

```bash
python cameras_app/app.py --help
python cameras_app/app.py --sem-ia                # inicia sem detecção de IA
python cameras_app/app.py --config outro.json      # config alternativo
python cameras_app/app.py --cameras outras.json    # lista de câmeras alternativa
```

Também é possível apontar arquivos alternativos via variáveis de ambiente
`VIGIACAM_CONFIG` e `VIGIACAM_CAMERAS`.

### Empacotar como app do macOS

```bash
./build_app.sh
```

Gera `build/VigiaCam.app` e instala um atalho na Área de Trabalho.

## Uso

1. Abra a aba **Ao Vivo** e escolha a categoria (sub-aba)
2. Clique num card para ampliar o vídeo
3. Use a aba **Câmeras** para adicionar/remover URLs (RTSP ou `.m3u8`)

As câmeras ficam salvas em `cameras_app/cameras.json`.

### Como descobrir o `.m3u8` de uma câmera de trânsito
Abra o portal (ex.: transitoaovivo.com) → F12 → aba **Network** →
filtre por `m3u8` → recarregue → copie a URL.

## Desenvolvimento

```bash
pip install -r requirements-dev.txt
pytest          # testes
ruff check .    # lint
```

Veja [CONTRIBUTING.md](CONTRIBUTING.md) para o fluxo de contribuição.

## Requisitos
- Python 3.9+
- `opencv-python`, `PySide6`, `ultralytics`
- Em alguns sistemas o RTSP exige ffmpeg instalado (`brew install ffmpeg`).

## Licença

[MIT](LICENSE)
