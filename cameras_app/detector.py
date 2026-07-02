"""Detecção de objetos leve com YOLOv8n (ultralytics).

O modelo "nano" (yolov8n) é o mais leve da família, roda em CPU e os
pesos (~6 MB) são baixados automaticamente no primeiro uso.

A API é dividida em duas etapas para permitir otimização:
- `detectar(frame)`  -> lista de detecções (caro: roda o modelo)
- `desenhar(frame, dets)` -> desenha caixas em cache (barato)

Assim a UI pode rodar `detectar` só 1x a cada N frames e `desenhar`
em todos, mantendo as caixas suaves com muito menos CPU.
"""

from __future__ import annotations

import threading

import cv2

try:
    from ultralytics import YOLO
    _DISPONIVEL = True
except ImportError:  # ultralytics não instalado
    _DISPONIVEL = False


def _cor(idx: int) -> tuple[int, int, int]:
    return (int(37 * (idx + 1)) % 256,
            int(17 * (idx + 3)) % 256,
            int(29 * (idx + 7)) % 256)


class Detector:
    """Wrapper de YOLO. Inferência reduzida (imgsz) + lock p/ threads."""

    def __init__(self, modelo="yolov8n.pt", conf=0.4, imgsz=480, classes=None,
                 device=None):
        if not _DISPONIVEL:
            raise RuntimeError(
                "ultralytics não instalado. Rode: pip install ultralytics")
        self.conf = conf
        self.imgsz = imgsz          # resolução de inferência (menor = mais rápido)
        self.classes = classes      # None = todas; ou lista de ids p/ filtrar
        self.device = device or self._melhor_device()  # Apple Silicon: 'mps'
        self.model = YOLO(modelo)    # baixa os pesos no 1o uso
        try:
            self.model.to(self.device)
        except Exception:
            self.device = "cpu"
            try:
                self.model.to("cpu")  # garante que o modelo realmente foi p/ CPU
            except Exception:
                pass
        self.nomes = self.model.names
        self._lock = threading.Lock()  # YOLO não é seguro p/ chamadas concorrentes

    @staticmethod
    def _melhor_device():
        """Escolhe o acelerador: MPS (Apple Silicon) > CUDA > CPU."""
        try:
            import torch
            if torch.backends.mps.is_available():
                return "mps"
            if torch.cuda.is_available():
                return "cuda"
        except Exception:
            pass
        return "cpu"

    @staticmethod
    def disponivel() -> bool:
        return _DISPONIVEL

    def detectar(self, frame):
        """Roda o modelo (etapa cara). Retorna lista de (x1,y1,x2,y2,cls,score)."""
        with self._lock:
            try:
                res = self.model.predict(
                    frame, conf=self.conf, imgsz=self.imgsz, device=self.device,
                    classes=self.classes, verbose=False)[0]
            except Exception:
                # acelerador instável (MPS/CUDA) -> cai p/ CPU e segue
                if self.device != "cpu":
                    self.device = "cpu"
                    self.model.to("cpu")
                    res = self.model.predict(
                        frame, conf=self.conf, imgsz=self.imgsz, device="cpu",
                        classes=self.classes, verbose=False)[0]
                else:
                    raise
        dets = []
        for box in res.boxes:
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            dets.append((x1, y1, x2, y2, int(box.cls[0]), float(box.conf[0])))
        return dets

    def desenhar(self, frame, dets):
        """Desenha as caixas (etapa barata). Retorna (frame, contagem)."""
        contagem = {}
        for x1, y1, x2, y2, cls, score in dets:
            nome = self.nomes.get(cls, str(cls))
            contagem[nome] = contagem.get(nome, 0) + 1
            cor = _cor(cls)
            cv2.rectangle(frame, (x1, y1), (x2, y2), cor, 2)
            rotulo = f"{nome} {score:.0%}"
            (tw, th), _ = cv2.getTextSize(rotulo, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
            cv2.rectangle(frame, (x1, y1 - th - 6), (x1 + tw, y1), cor, -1)
            cv2.putText(frame, rotulo, (x1, y1 - 4),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        return frame, contagem
