# Fine-tuning do modelo de detecção (Fase 4 do plano de precisão)

O teto de precisão dos modelos COCO genéricos nas SUAS câmeras é ~60-70%.
Passar disso exige treinar com frames reais das próprias câmeras. Este kit
fecha o ciclo: coletar → anotar → treinar → exportar → colocar no app.

## 1. Coletar frames

Os snapshots do app já servem de matéria-prima (ficam em
`~/Documents/VigiaCam/capturas`, com cadeia de custódia). Para volume, use o
botão Snapshot nas câmeras-alvo em horários/condições variados (dia, noite,
chuva) — 300+ imagens por câmera é um bom começo, 1000+ é confortável.

```bash
./coletar_frames.sh   # copia capturas p/ dataset/images_brutas (sem tocar nos originais)
```

## 2. Anotar

Use o [Label Studio](https://labelstud.io) (`pip install label-studio`) ou o
[CVAT](https://cvat.ai), exportando no formato **YOLO** (um `.txt` por imagem:
`classe cx cy w h` normalizados). Anote SÓ as classes que importam pro negócio
(pessoa, veículos, EPI...) — poucas classes bem anotadas > muitas mal anotadas.
Lição do harness deste repo: não anote a olho caixas <20px; envenenam a métrica
e o treino.

## 3. Preparar dataset

```bash
python3 preparar_dataset.py dataset/images_anotadas --classes "person,car,truck" --val 0.15
```

Gera a estrutura `dataset/{train,val}/{images,labels}` + `data.yaml` prontos
para o Ultralytics.

## 4. Treinar (neste Mac, MPS)

```bash
./treinar.sh              # yolo11s, 100 epochs, imgsz 640, device mps
./treinar.sh 960          # variante longa distância
```

Regras aprendidas no projeto finetuning-mlx: use o checkpoint de MENOR val
loss (o `best.pt` do Ultralytics já faz isso), não o último.

## 5. Exportar e instalar no app

O `treinar.sh` já exporta `best.pt` → CoreML (`nms=False`, como o app espera).
Depois:

```bash
cp -R runs/detect/train/weights/best_saved_model/best.mlpackage \
      ../VigiaCam/Sources/VigiaCam/Resources/meumodelo.mlpackage
```

E no código: adicionar um case em `TipoModelo` (DetectorService.swift) com
`arquivo = "meumodelo"` + os labels na ordem de treino (ver `ClassesModelo.swift`
— use array de tuplas, NUNCA literal de dicionário grande, o type-check trava).
O parse [4+classes, N] e o letterbox já são genéricos (inclusive strides não
contíguos, corrigido na Fase 3).

## 6. Validar ANTES de adotar

```bash
VIGIA_CHAVE_TESTE=1 ../VigiaCam/.build/release/VigiaCam --eval ../Tests-fixtures/coco -tipoModeloAtivo <caso>
```

E monte fixtures das suas câmeras (imagem + JSON de GT em pixels topo-esquerdo,
formato no cabeçalho do EvalRunner.swift) — o número que importa é o do SEU
cenário, não o do COCO.

## Referência de baseline (30/ago/2026, Tests-fixtures/coco, 52 classes)

| Modelo | Precisão | Recall |
|---|---|---|
| yolov8n (Rápido) | 63% | 46% |
| yolo11s (Preciso) | 60% | 54% |
| yolo11s960 (Longa distância) | 54% | 58% |
