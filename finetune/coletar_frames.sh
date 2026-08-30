#!/bin/bash
# Copia os snapshots do VigiaCam para a área de trabalho do dataset.
# Só COPIA — os originais (com cadeia de custódia) ficam intactos.
set -euo pipefail
ORIGEM="$HOME/Documents/VigiaCam/capturas"
DESTINO="$(dirname "$0")/dataset/images_brutas"
mkdir -p "$DESTINO"
n=$(find "$ORIGEM" -name "*.png" -o -name "*.jpg" 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -eq 0 ] && { echo "Nenhum snapshot em $ORIGEM — capture pelo app primeiro."; exit 1; }
rsync -a --include='*.png' --include='*.jpg' --exclude='*' "$ORIGEM/" "$DESTINO/"
echo "✅ $n imagens copiadas para $DESTINO — agora anote (Label Studio/CVAT, formato YOLO)."
