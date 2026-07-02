# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e o versionamento segue [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Adicionado
- Suite de testes automatizados (`pytest`) para validação de config, URLs e
  normalização de câmeras.
- CI no GitHub Actions (lint com `ruff` + testes).
- CLI com `argparse` (`--config`, `--cameras`, `--sem-ia`).
- Suporte a variáveis de ambiente `VIGIACAM_CONFIG` e `VIGIACAM_CAMERAS`
  para apontar arquivos alternativos.
- Type hints nas funções puras de `app.py` e `detector.py`.
- Metadados de projeto em `pyproject.toml`.
- Documentação de contribuição, código de conduta e política de segurança.

### Alterado
- Removida cópia duplicada de `yolov8n.pt` (o modelo já é baixado
  automaticamente pelo `ultralytics` no primeiro uso).

## [1.0.0] - 2026-06-15

- Versão inicial: mural de câmeras RTSP/HLS com detecção YOLOv8n, dashboard
  operacional, gestão de câmeras e configurações de performance/IA.
