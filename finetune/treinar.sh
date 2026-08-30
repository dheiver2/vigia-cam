#!/bin/bash
# Fine-tuning do yolo11s com o dataset preparado + export CoreML p/ o app.
# Uso: ./treinar.sh [imgsz]   (default 640; use 960 p/ longa distância)
set -euo pipefail
cd "$(dirname "$0")"
IMGSZ="${1:-640}"
[ -f dataset/data.yaml ] || { echo "rode preparar_dataset.py antes"; exit 1; }
python3 -m pip show ultralytics >/dev/null 2>&1 || python3 -m pip install ultralytics coremltools

# device=mps usa a GPU do Apple Silicon; batch -1 = auto pelo VRAM.
yolo detect train model=yolo11s.pt data=dataset/data.yaml \
    epochs=100 imgsz="$IMGSZ" device=mps batch=-1 patience=25

BEST=$(ls -t runs/detect/train*/weights/best.pt | head -1)
echo "→ exportando $BEST para CoreML (nms=False, como o app espera)"
yolo export model="$BEST" format=coreml imgsz="$IMGSZ" nms=False
echo "✅ mlpackage em $(dirname "$BEST") — siga o passo 5 do README para instalar no app."
