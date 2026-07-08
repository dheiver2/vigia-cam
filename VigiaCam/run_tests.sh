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
  "Tests-cli/main.swift"

echo "== Executando testes =="
"$OUT"
