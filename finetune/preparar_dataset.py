#!/usr/bin/env python3
"""Monta dataset/{train,val} + data.yaml a partir de imagens anotadas em YOLO.

Uso:
    python3 preparar_dataset.py <dir com .jpg/.png + .txt YOLO> \
        --classes "person,car,truck" [--val 0.15]

O split é determinístico (hash do nome do arquivo), então rodar de novo com
imagens novas NÃO embaralha o val antigo — evita vazamento treino→val entre
iterações do dataset.
"""
import argparse, hashlib, shutil, sys
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("origem", type=Path)
ap.add_argument("--classes", required=True, help="nomes na ordem dos índices das anotações")
ap.add_argument("--val", type=float, default=0.15)
args = ap.parse_args()

classes = [c.strip() for c in args.classes.split(",") if c.strip()]
raiz = Path(__file__).parent / "dataset"
imagens = sorted(p for p in args.origem.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
pares = [(img, img.with_suffix(".txt")) for img in imagens if img.with_suffix(".txt").exists()]
if not pares:
    sys.exit(f"nenhum par imagem+.txt em {args.origem} — anote antes (formato YOLO)")

n_val = 0
for img, txt in pares:
    # split determinístico por hash do nome
    h = int(hashlib.sha1(img.name.encode()).hexdigest(), 16) % 1000
    lote = "val" if h < args.val * 1000 else "train"
    n_val += lote == "val"
    for sub, src in (("images", img), ("labels", txt)):
        destino = raiz / lote / sub
        destino.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, destino / src.name)

yaml = raiz / "data.yaml"
yaml.write_text(
    f"path: {raiz.resolve()}\ntrain: train/images\nval: val/images\n"
    f"nc: {len(classes)}\nnames: {classes}\n"
)
print(f"✅ {len(pares)} pares ({n_val} val) — {yaml}")
