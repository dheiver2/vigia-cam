#!/usr/bin/env bash
# Testes de lógica pura que rodam SEM Xcode (só Command Line Tools).
# Compila os fontes reais + Tests-cli/main.swift num binário e executa.
# Para a suíte XCTest completa (requer Xcode): swift test
set -euo pipefail
cd "$(dirname "$0")"

SRC="Sources/VigiaCam"
OUT="$(mktemp -d)/vigia_tests"

swiftc -o "$OUT" \
  "$SRC/Features/Cameras/Models/Camera.swift" \
  "$SRC/Features/Alarms/AlarmModels.swift" \
  "$SRC/Features/Detection/ObjectTracker.swift" \
  "$SRC/Features/Business/BusinessAnalytics.swift" \
  "$SRC/Core/Security/CryptoService.swift" \
  "$SRC/Features/Config/AppConfig.swift" \
  "$SRC/Features/Detection/ClassesModelo.swift" \
  "$SRC/Features/Detection/NightBoostService.swift" \
  "Tests-cli/main.swift"

echo "== Executando testes =="
# Chave em memória: binário de teste não assinado tocando o Keychain dispara
# diálogo de senha do macOS e trava a suíte.
VIGIA_CHAVE_TESTE=1 "$OUT"
