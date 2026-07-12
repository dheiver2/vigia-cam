# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e o versionamento segue [SemVer](https://semver.org/lang/pt-BR/).

## [2.0.0] - 2026-07-12

Reescrita completa 100% nativa em Swift/SwiftUI para macOS (a versão
Python/OpenCV foi descontinuada).

### Adicionado
- App desktop nativo SwiftUI (macOS 14+) via SwiftPM, sem dependências externas.
- Detecção de objetos on-device com YOLOv8n via Core ML/Vision (parsing raw,
  NMS e rastreador de objetos próprios).
- Videowall ao vivo com modo ronda e visão detalhada por câmera (RTSP/HLS).
- Motor de alarmes por regra com eventos e trilha de auditoria.
- Gravação MP4 e capturas com cadeia de custódia (hash SHA-256).
- Máscaras de privacidade (LGPD) e relatórios em PDF.
- Controle de acesso RBAC (PBKDF2) e criptografia de configuração/usuários
  (AES-GCM com chave no Keychain).
- Módulo de analytics de negócio por nicho.
- Suíte de testes (XCTest + runner CLI sem Xcode) e CI no GitHub Actions.

### Removido
- Toda a implementação Python (Flask/OpenCV/ultralytics), pytest e ruff.

## [1.0.0] - 2026-06-15

- Versão inicial (Python): mural de câmeras RTSP/HLS com detecção YOLOv8n,
  dashboard operacional, gestão de câmeras e configurações de performance/IA.
