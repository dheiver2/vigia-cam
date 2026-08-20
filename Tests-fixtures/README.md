# Fixtures de avaliação de detecção

Base de comparação do plano de qualidade das detecções. Rodar:

```
VigiaCam/.build/release/VigiaCam --eval Tests-fixtures
```

(ou `VigiaCam.app/Contents/MacOS/VigiaCam --eval Tests-fixtures`)

Cada `imagem.jpg` com um `imagem.json` ao lado é avaliada; imagens sem JSON
são ignoradas (material aguardando anotação). Formato do ground-truth —
pixels, origem no canto superior-esquerdo:

```json
[{"label": "bus", "x1": 12, "y1": 230, "x2": 809, "y2": 740}]
```

Critério: TP = mesma classe e IoU >= 0,5 (associação gulosa, padrão VOC).

## Baseline (19/ago/2026, yolov8n, conf 0,25)

| imagem  | classe | TP | FP | FN | precisão | recall | IoU médio |
|---------|--------|----|----|----|----------|--------|-----------|
| bus.jpg | bus    | 1  | 0  | 0  | 100%     | 100%   | 0,93      |
| bus.jpg | person | 4  | 0  | 0  | 100%     | 100%   | 0,94      |

`nysdot_R8_018.jpg` (rodovia à noite) está aqui como material para anotação
cuidadosa — anotar a olho caixas de ~20px geraria ground-truth ruim, que é
pior que nenhum. Anotar com ferramenta (ex. LabelStudio) antes de graduar.
