// Detecção YOLOv8n via onnxruntime-web (WASM) — porte do DetectorService.swift.
// Saída do modelo: [1, 84, 8400] (4 box + 80 classes COCO), NMS feito à mão.
const COCO_CLASSES = ["person","bicycle","car","motorcycle","airplane","bus","train","truck","boat","traffic light","fire hydrant","stop sign","parking meter","bench","bird","cat","dog","horse","sheep","cow","elephant","bear","zebra","giraffe","backpack","umbrella","handbag","tie","suitcase","frisbee","skis","snowboard","sports ball","kite","baseball bat","baseball glove","skateboard","surfboard","tennis racket","bottle","wine glass","cup","fork","knife","spoon","bowl","banana","apple","sandwich","orange","broccoli","carrot","hot dog","pizza","donut","cake","chair","couch","potted plant","bed","dining table","toilet","tv","laptop","mouse","remote","keyboard","cell phone","microwave","oven","toaster","sink","refrigerator","book","clock","vase","scissors","teddy bear","hair drier","toothbrush"]
const CLASS_PT = { person: "pessoa", car: "carro", truck: "caminhão", bus: "ônibus", motorcycle: "moto", bicycle: "bicicleta", dog: "cachorro", cat: "gato", "traffic light": "semáforo" }

const Detector = (() => {
  const ort = require('onnxruntime-web')
  const path = require('path')
  const IMG = 640
  let session = null
  let loading = null

  async function ensure() {
    if (session) return session
    if (!loading) {
      // Empacotado, os .wasm/.mjs e o modelo ficam fora do asar (asarUnpack):
      // fetch()/import() não leem de dentro do arquivo asar.
      const root = path.join(__dirname, '..').replace('app.asar', 'app.asar.unpacked')
      ort.env.wasm.wasmPaths = path.join(root, 'node_modules', 'onnxruntime-web', 'dist') + path.sep
      ort.env.wasm.numThreads = 1
      loading = ort.InferenceSession.create(path.join(root, 'app', 'yolov8n.onnx'), { executionProviders: ['wasm'] })
        .then(s => { session = s; return s })
    }
    return loading
  }

  const work = document.createElement('canvas')
  work.width = IMG; work.height = IMG
  const wctx = work.getContext('2d', { willReadFrequently: true })

  // Letterbox igual ao Vision (scaleFit): mantém proporção, barras pretas.
  // Luminância média (0–1, Rec. 709) amostrando 1 a cada 16 pixels — barato.
  function lumaMedia(data) {
    let soma = 0, n = 0
    for (let i = 0; i < data.length; i += 64) {
      soma += 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]
      n++
    }
    return n ? soma / n / 255 : 1
  }
  const LIMIAR_ESCURO = 0.25

  function preprocess(video, modoNoturno) {
    const vw = video.videoWidth, vh = video.videoHeight
    if (!vw || !vh) return null
    const scale = Math.min(IMG / vw, IMG / vh)
    const nw = Math.round(vw * scale), nh = Math.round(vh * scale)
    const dx = (IMG - nw) / 2, dy = (IMG - nh) / 2
    wctx.fillStyle = '#000'; wctx.fillRect(0, 0, IMG, IMG)
    wctx.drawImage(video, dx, dy, nw, nh)
    let { data } = wctx.getImageData(0, 0, IMG, IMG)
    // Modo noturno (paridade com o NightBoost do macOS): realce de baixa luz
    // ANTES da inferência. Redesenha com filtro só quando necessário — de dia
    // no modo "auto" não custa nada.
    if (modoNoturno === 'sempre' || (modoNoturno === 'auto' && lumaMedia(data) < LIMIAR_ESCURO)) {
      wctx.filter = 'brightness(1.9) contrast(1.15) saturate(1.15)'
      wctx.fillStyle = '#000'; wctx.fillRect(0, 0, IMG, IMG)
      wctx.drawImage(video, dx, dy, nw, nh)
      wctx.filter = 'none'
      ;({ data } = wctx.getImageData(0, 0, IMG, IMG))
    }
    const f = new Float32Array(3 * IMG * IMG)
    const area = IMG * IMG
    for (let i = 0; i < area; i++) {
      f[i] = data[i * 4] / 255
      f[area + i] = data[i * 4 + 1] / 255
      f[2 * area + i] = data[i * 4 + 2] / 255
    }
    return { tensor: new ort.Tensor('float32', f, [1, 3, IMG, IMG]), scale, dx, dy, vw, vh }
  }

  function iou(a, b) {
    const x1 = Math.max(a.x, b.x), y1 = Math.max(a.y, b.y)
    const x2 = Math.min(a.x + a.w, b.x + b.w), y2 = Math.min(a.y + a.h, b.y + b.h)
    const inter = Math.max(0, x2 - x1) * Math.max(0, y2 - y1)
    return inter / (a.w * a.h + b.w * b.h - inter)
  }

  // Parse [84,8400] + NMS — mesma convenção do parse manual no Swift.
  function postprocess(out, meta, conf, classesAtivas) {
    const d = out.data, N = 8400
    let cands = []
    for (let i = 0; i < N; i++) {
      let best = 0, cls = -1
      for (let c = 0; c < 80; c++) {
        const s = d[(4 + c) * N + i]
        if (s > best) { best = s; cls = c }
      }
      if (best < conf) continue
      const name = COCO_CLASSES[cls]
      if (classesAtivas && !classesAtivas.includes(name)) continue
      const cx = d[i], cy = d[N + i], w = d[2 * N + i], h = d[3 * N + i]
      cands.push({ x: cx - w / 2, y: cy - h / 2, w, h, score: best, cls: name })
    }
    cands.sort((a, b) => b.score - a.score)
    const kept = []
    for (const c of cands) {
      if (kept.length >= 50) break
      if (kept.every(k => k.cls !== c.cls || iou(k, c) < 0.45)) kept.push(c)
    }
    // volta do espaço letterbox 640 pro frame original
    return kept.map(k => ({
      cls: k.cls, label: CLASS_PT[k.cls] || k.cls, score: k.score,
      x: (k.x - meta.dx) / meta.scale, y: (k.y - meta.dy) / meta.scale,
      w: k.w / meta.scale, h: k.h / meta.scale
    }))
  }

  let busy = false
  async function detect(video, conf, classesAtivas, modoNoturno) {
    if (busy) return null
    busy = true
    try {
      const s = await ensure()
      const meta = preprocess(video, modoNoturno)
      if (!meta) return null
      const out = await s.run({ [s.inputNames[0]]: meta.tensor })
      return postprocess(out[s.outputNames[0]], meta, conf, classesAtivas)
    } catch (e) {
      console.error('detector:', e.message)
      return null
    } finally { busy = false }
  }

  return { detect, COCO_CLASSES, CLASS_PT }
})()
