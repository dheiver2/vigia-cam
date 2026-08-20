# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e o versionamento segue [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Adicionado
- Harness de métricas de detecção: `VigiaCam --eval Tests-fixtures` roda o
  pipeline real (Vision/CoreML) sobre imagens com ground-truth e imprime
  precisão/recall/IoU por classe; baseline registrado em Tests-fixtures/.
- Tradução PT-BR completa das 90 classes (COCO + EPI) numa fonte única
  (`ClassesPT`), usada no overlay dos cards e nas regras de alarme; teste
  garante que nenhuma classe fica sem tradução. Porte Windows idem (80 COCO).
- Windows: votação de maioria da classe por track (janela 5) e histerese de
  exibição (2 confirmações) — paridade com o ObjectTracker do macOS; acaba o
  "car↔truck" piscando e as caixas-fantasma de 1 frame.

## [2.4.0] - 2026-08-19

### Adicionado
- Modo noturno de detecção (Desligado/Auto/Sempre): realce de baixa luz
  (sombras + exposição + gamma + redução de ruído via Core Image) aplicado ao
  frame antes do YOLO; em "Auto" só entra quando a luminância média da cena
  cai abaixo de 25%.
- Modelo "Preciso" (YOLOv8s) selecionável em Configurações, ao lado do v8n —
  melhor recall em objetos pequenos/distantes (~2× o custo por inferência,
  ainda folgado para 60 FPS).
- Mapa de calor de circulação por câmera: overlay ao vivo e acumulado por
  período (buckets persistidos no SQLite), reaproveitando as caixas do
  detector — sem modelo novo.
- Descoberta automática de câmeras ONVIF na rede (WS-Discovery) com
  importação direta para a lista de câmeras.
- Relatórios de negócio por período com deltas corretos de contadores
  cumulativos (técnica de reset à la rate() do Prometheus).

### Adicionado
- Windows: modo noturno de detecção (Desligado/Auto/Sempre) no porte Electron
  — mesmo realce de baixa luz antes do ONNX; zip da edição Windows voltou a
  acompanhar a release (nota: a edição Windows tem escopo reduzido — sem
  SQLite/LPR/mapa/auto-update do macOS).

### Alterado
- App assinado com Developer ID + hardened runtime (antes ad-hoc): o Keychain
  para de pedir senha a cada atualização do app.

## [2.3.0] - 2026-08-05

### Adicionado
- Auto-update via GitHub Releases: "Verificar agora" em Configurações ›
  Alarmes consulta a última versão; com update disponível, um clique baixa o
  zip, troca o próprio .app (com backup/rollback e remoção de quarentena) e
  reabre o app na versão nova.

## [2.2.0] - 2026-08-05

Pacote "central de monitoramento": gestão, investigação e novos analíticos.

### Adicionado
- Autenticação local com papéis (admin/operador/visualizador), PBKDF2-SHA256,
  gestão de usuários e tela de trilha de auditoria (RBAC prometido no README
  agora existe de verdade).
- Banco SQLite de eventos (busca por texto/câmera/tipo, tratativa "checado
  por", evidência ligada ao evento) — o CSV continua sendo escrito.
- Log persistente de status online/offline por câmera + painel de contadores
  de ocorrências por tipo no Dashboard.
- Mapa de câmeras (MapKit) com pins coloridos pelo estado real do stream.
- LPR: leitura de placas BR (Mercosul/antiga) via Vision sobre as caixas de
  veículo do YOLO, com busca histórica e lista de placas de interesse
  (dispara alarme crítico).
- Novos analíticos de zona: evasão (saída da zona) e ausência (zona vazia
  além do tolerado); detecção de mudança de cena (câmera tampada/movida).
- Aba Gravações: playback de clipes dentro do app, exportação de evidência e
  time lapse acelerado (4–32×) via ffmpeg.
- Notificações do sistema (Central de Notificações) por alarme; webhook,
  som, snapshot automático e LPR agora configuráveis pela UI.
- Série temporal das métricas de negócio persistida (1 amostra/min/câmera).

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
