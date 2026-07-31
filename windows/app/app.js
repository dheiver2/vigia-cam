// VIGIA·CAM — porte Windows (Electron). Mesma UI/fluxo do app macOS nativo.
const { ipcRenderer } = require('electron')
const fs = require('fs')
const path = require('path')
const os = require('os')

// Pasta de mídia (snapshots/gravações) — espelha o ~/Documents/VigiaCam do macOS
const MEDIA_DIR = path.join(os.homedir(), 'Documents', 'VigiaCam')
try { fs.mkdirSync(path.join(MEDIA_DIR, 'midia'), { recursive: true }) } catch (e) {}

// ---------- Estado / storage (localStorage no lugar do cameras.json) ----------
const store = {
  get cameras() {
    let v = JSON.parse(localStorage.getItem('cameras') || 'null')
    if (!v || !v.length) { v = CAMERAS_SEED.slice(); localStorage.setItem('cameras', JSON.stringify(v)) }
    return v
  },
  set cameras(v) { localStorage.setItem('cameras', JSON.stringify(v)) },
  get config() {
    return Object.assign({ fpsMax: 15, confianca: 0.40, deteccao: true, som: true, webhook: '', osd: true }, JSON.parse(localStorage.getItem('config') || '{}'))
  },
  set config(v) { localStorage.setItem('config', JSON.stringify(v)) },
  get alarmes() {
    let v = JSON.parse(localStorage.getItem('alarmes') || 'null')
    if (!v) {
      v = [
        { nome: 'Aglomeração', classe: 'person', limite: 5, severidade: 'aviso', ativo: true },
        { nome: 'Caminhão em via', classe: 'truck', limite: 1, severidade: 'info', ativo: true },
        { nome: 'Congestionamento', classe: 'car', limite: 8, severidade: 'critico', ativo: true },
      ]
      localStorage.setItem('alarmes', JSON.stringify(v))
    }
    return v
  },
  set alarmes(v) { localStorage.setItem('alarmes', JSON.stringify(v)) },
  get privacidade() { return JSON.parse(localStorage.getItem('privacidade') || '{}') },
  set privacidade(v) { localStorage.setItem('privacidade', JSON.stringify(v)) },
  eventos: JSON.parse(localStorage.getItem('eventos') || '[]'),
  registrarEvento(tipo, camera, detalhe, severidade) {
    this.eventos.unshift({ ts: Date.now(), tipo, camera, detalhe, severidade })
    this.eventos = this.eventos.slice(0, 1000)
    localStorage.setItem('eventos', JSON.stringify(this.eventos))
  },
  // Cadeia de custódia: hash SHA-256 de cada mídia salva (paridade com o macOS)
  custodia(arquivo, sha) {
    const linha = `${new Date().toISOString()},${arquivo},${sha}\n`
    try { fs.appendFileSync(path.join(MEDIA_DIR, 'custodia.csv'), linha) } catch (e) {}
  }
}

const state = {
  tab: 'cameras', grid: 2, categoria: 'Todas', busca: '', pagina: 0, ronda: false,
  players: [], contagens: {}, online: new Set(),
  foco: null,           // url da câmera em tela cheia (duplo clique)
  editZonas: false,     // modo edição de zonas de privacidade (só no foco)
  saude: JSON.parse(sessionStorage.getItem('saude') || '{}'),  // url -> {reconexoes, desdeTs}
  gravando: {},         // url -> MediaRecorder
}

function saudeDe(url) {
  if (!state.saude[url]) state.saude[url] = { reconexoes: 0, desdeTs: Date.now() }
  return state.saude[url]
}
function salvaSaude() { sessionStorage.setItem('saude', JSON.stringify(state.saude)) }

// ---------- Navegação ----------
const TABS = [
  ['cameras', 'Ao Vivo', 'M2 5a2 2 0 012-2h7a2 2 0 012 2v6a2 2 0 01-2 2H4a2 2 0 01-2-2V5zm12 1.5l3.6-2.4a.5.5 0 01.9.4v7a.5.5 0 01-.9.4L14 9.5v-3z'],
  ['alarms', 'Alarmes', 'M8 1a4 4 0 00-4 4v3L2.5 10.5a.7.7 0 00.5 1.2h10a.7.7 0 00.5-1.2L12 8V5a4 4 0 00-4-4zm0 14a2 2 0 002-2H6a2 2 0 002 2z'],
  ['business', 'Negócio', 'M1 14h14v1H1v-1zm1-4l3-3 2.5 2.5L12 5l2 2V3h-4l1.3 1.3-3.8 3.9L5 5.7 1 9.7V10z'],
  ['dashboard', 'Dashboard', 'M2 9h4v5H2V9zm5-6h4v11H7V3zm5 3h4v8h-4V6z'],
  ['events', 'Eventos', 'M9 1L3 9h4l-1 6 6-8H8l1-6z'],
  ['reports', 'Relatórios', 'M4 1h6l3 3v11H4V1zm6 0v3h3M6 7h5M6 9.5h5M6 12h3'],
  ['config', 'Configurações', 'M8 5a3 3 0 100 6 3 3 0 000-6zm6.5 3a5 5 0 01-.1 1l1.5 1.2-1.5 2.6-1.8-.7a6 6 0 01-1.7 1L10.6 15H7.4l-.3-1.9a6 6 0 01-1.7-1l-1.8.7L2.1 10.2 3.6 9a5 5 0 010-2L2.1 5.8l1.5-2.6 1.8.7a6 6 0 011.7-1L7.4 1h3.2l.3 1.9a6 6 0 011.7 1l1.8-.7 1.5 2.6L14.4 7a5 5 0 01.1 1z'],
]

function renderNav() {
  document.getElementById('nav').innerHTML = TABS.map(([tag, label, path]) =>
    `<div class="nav-btn ${state.tab === tag ? 'active' : ''}" data-tab="${tag}">
       <svg viewBox="0 0 16 16"><path d="${path}"/></svg>${label}</div>`).join('')
  document.querySelectorAll('.nav-btn').forEach(b =>
    b.onclick = () => { state.tab = b.dataset.tab; state.foco = null; render() })
}

// ---------- Ao Vivo (videowall) ----------
function categorias() { return ['Todas', ...new Set(store.cameras.map(c => c.categoria))] }

function camerasFiltradas() {
  return store.cameras.filter(c =>
    (state.categoria === 'Todas' || c.categoria === state.categoria) &&
    (!state.busca || c.nome.toLowerCase().includes(state.busca.toLowerCase())))
}

function renderLive(el) {
  destroyPlayers()
  const cams = camerasFiltradas()

  // Tela cheia de uma câmera (duplo clique) — com editor de zonas de privacidade
  if (state.foco) {
    const cam = store.cameras.find(c => c.url === state.foco)
    if (!cam) { state.foco = null; return renderLive(el) }
    el.innerHTML = `
      <div class="toolbar">
        <button class="btn ghost" id="voltar">‹ Voltar (Esc)</button>
        <span style="font-weight:700;font-size:13px">${cam.nome}</span>
        <button class="btn ghost" id="zonas">${state.editZonas ? '✓ Concluir zonas' : '▦ Zonas de privacidade'}</button>
        <button class="btn ghost" id="limpar-zonas">Limpar zonas</button>
        <span class="cam-count">arraste sobre o vídeo para criar uma zona</span>
      </div>
      <div id="wall" style="grid-template-columns:1fr;grid-template-rows:1fr"></div>`
    el.querySelector('#voltar').onclick = () => { state.foco = null; state.editZonas = false; render() }
    el.querySelector('#zonas').onclick = () => { state.editZonas = !state.editZonas; render() }
    el.querySelector('#limpar-zonas').onclick = () => {
      const p = store.privacidade; delete p[cam.url]; store.privacidade = p; render()
    }
    el.querySelector('#wall').appendChild(criaCard(cam))
    return
  }

  const porPagina = state.grid * state.grid
  const paginas = Math.max(1, Math.ceil(cams.length / porPagina))
  state.pagina = Math.min(state.pagina, paginas - 1)
  const visiveis = cams.slice(state.pagina * porPagina, (state.pagina + 1) * porPagina)

  el.innerHTML = `
    <div class="toolbar">
      <div class="grid-btns">${[1, 2, 3, 4].map(n =>
        `<span class="grid-btn ${state.grid === n ? 'active' : ''}" data-g="${n}">${n}×${n}</span>`).join('')}</div>
      <select id="cat">${categorias().map(c => `<option ${c === state.categoria ? 'selected' : ''}>${c}</option>`).join('')}</select>
      <input type="text" id="busca" placeholder="Buscar..." value="${state.busca}">
      <div class="pager">
        <button id="prev">‹</button> Página ${state.pagina + 1}/${paginas} <button id="next">›</button>
      </div>
      <span class="ronda-btn ${state.ronda ? 'active' : ''}" id="ronda">◉ Ronda</span>
      <span class="cam-count" title="Atalhos: 1-4 grade · ←/→ página · R ronda · duplo clique = tela cheia">${cams.length} câmeras · ⌨</span>
    </div>
    <div id="wall" style="grid-template-columns:repeat(${state.grid},1fr);grid-template-rows:repeat(${state.grid},1fr)"></div>`

  el.querySelectorAll('.grid-btn').forEach(b => b.onclick = () => { state.grid = +b.dataset.g; render() })
  el.querySelector('#cat').onchange = e => { state.categoria = e.target.value; state.pagina = 0; render() }
  el.querySelector('#busca').oninput = e => { state.busca = e.target.value; state.pagina = 0; renderSoWall(el) }
  el.querySelector('#prev').onclick = () => { state.pagina = Math.max(0, state.pagina - 1); render() }
  el.querySelector('#next').onclick = () => { state.pagina = Math.min(paginas - 1, state.pagina + 1); render() }
  el.querySelector('#ronda').onclick = () => { state.ronda = !state.ronda; render() }

  const wall = el.querySelector('#wall')
  visiveis.forEach(cam => wall.appendChild(criaCard(cam)))
  if (state.ronda) state.rondaTimer = setTimeout(() => { state.pagina = (state.pagina + 1) % paginas; render() }, 10000)
}

function renderSoWall() {
  clearTimeout(state.buscaTimer)
  state.buscaTimer = setTimeout(() => render(), 400)
}

function criaCard(cam) {
  const card = document.createElement('div')
  card.className = 'cam-card'
  card.innerHTML = `
    <span class="cam-status">OFFLINE</span>
    <span class="cam-meta"><span class="osd-clock"></span> · <span class="fps">0 fps</span></span>
    <video muted autoplay playsinline></video>
    <canvas class="overlay"></canvas>
    <div class="cam-actions">
      <button class="act-btn" data-act="snap" title="Snapshot com carimbo + SHA-256">📷</button>
      <button class="act-btn" data-act="rec" title="Gravar vídeo">⏺</button>
    </div>
    <span class="cam-name">${cam.nome}</span>`
  const video = card.querySelector('video')
  const status = card.querySelector('.cam-status')
  const overlay = card.querySelector('canvas.overlay')

  // OSD: relógio ao vivo por tile
  const clock = card.querySelector('.osd-clock')
  const tickClock = () => clock.textContent = new Date().toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' })
  tickClock()
  const clockTimer = store.config.osd ? setInterval(tickClock, 1000) : null

  if (Hls.isSupported()) {
    const hls = new Hls({ manifestLoadingMaxRetry: 4, fragLoadingMaxRetry: 4 })
    hls.loadSource(cam.url)
    hls.attachMedia(video)
    hls.on(Hls.Events.FRAG_LOADED, () => {
      if (!state.online.has(cam.url)) saudeDe(cam.url).desdeTs = Date.now()
      status.textContent = 'AO VIVO'; status.classList.add('live'); state.online.add(cam.url)
      card.querySelector('.cam-err')?.remove(); video.style.display = ''
    })
    hls.on(Hls.Events.ERROR, (_, d) => {
      if (d.fatal) {
        if (state.online.has(cam.url)) { saudeDe(cam.url).reconexoes++; salvaSaude() }
        state.online.delete(cam.url)
        status.textContent = 'OFFLINE'; status.classList.remove('live')
        video.style.display = 'none'
        if (!card.querySelector('.cam-err'))
          card.insertAdjacentHTML('beforeend', '<div class="cam-err">⚠ Sem resposta do servidor<small>reconectando…</small></div>')
        setTimeout(() => { try { hls.startLoad() } catch (e) {} }, 8000)
      }
    })
    state.players.push({ hls, video, overlay, cam, clockTimer, timer: iniciaDeteccao(video, overlay, card, cam) })
  }

  // Ações: snapshot e gravação
  card.querySelector('[data-act="snap"]').onclick = e => { e.stopPropagation(); snapshot(video, overlay, cam) }
  const recBtn = card.querySelector('[data-act="rec"]')
  if (state.gravando[cam.url]) recBtn.classList.add('rec-on')
  recBtn.onclick = e => { e.stopPropagation(); toggleGravacao(video, cam, recBtn) }

  // Duplo clique: tela cheia
  card.ondblclick = () => {
    if (state.editZonas) return
    state.foco = state.foco ? null : cam.url
    render()
  }

  // Editor de zonas de privacidade (arraste no modo edição)
  if (state.editZonas && state.foco === cam.url) instalaEditorZonas(card, overlay, cam)
  return card
}

// ---------- Zonas de privacidade (LGPD) ----------
function zonasDe(cam) { return store.privacidade[cam.url] || [] }

function instalaEditorZonas(card, overlay, cam) {
  card.style.cursor = 'crosshair'
  let ini = null
  card.onmousedown = e => { ini = { x: e.offsetX / card.clientWidth, y: e.offsetY / card.clientHeight } }
  card.onmouseup = e => {
    if (!ini) return
    const fim = { x: e.offsetX / card.clientWidth, y: e.offsetY / card.clientHeight }
    const z = { x: Math.min(ini.x, fim.x), y: Math.min(ini.y, fim.y), w: Math.abs(fim.x - ini.x), h: Math.abs(fim.y - ini.y) }
    if (z.w > 0.02 && z.h > 0.02) {
      const p = store.privacidade
      p[cam.url] = [...(p[cam.url] || []), z]
      store.privacidade = p
      store.registrarEvento('privacidade', cam.nome, 'Zona de privacidade adicionada', 'info')
    }
    ini = null
  }
}

function desenhaZonas(ctx, w, h, cam) {
  for (const z of zonasDe(cam)) {
    ctx.fillStyle = '#000'
    ctx.fillRect(z.x * w, z.y * h, z.w * w, z.h * h)
    ctx.fillStyle = 'rgba(255,255,255,0.25)'
    ctx.font = 'bold 9px Segoe UI'
    ctx.fillText('PRIVACIDADE', z.x * w + 4, z.y * h + 12)
  }
}

// ---------- Snapshot com carimbo + cadeia de custódia ----------
async function snapshot(video, overlay, cam) {
  if (!video.videoWidth) return
  const c = document.createElement('canvas')
  c.width = video.videoWidth; c.height = video.videoHeight
  const ctx = c.getContext('2d')
  ctx.drawImage(video, 0, 0)
  desenhaZonas(ctx, c.width, c.height, cam)
  const carimbo = `${cam.nome} — ${new Date().toLocaleString('pt-BR')}`
  ctx.font = 'bold 16px Segoe UI'
  ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(0, c.height - 28, ctx.measureText(carimbo).width + 20, 28)
  ctx.fillStyle = '#fff'; ctx.fillText(carimbo, 10, c.height - 9)
  const blob = await new Promise(r => c.toBlob(r, 'image/png'))
  const buf = Buffer.from(await blob.arrayBuffer())
  const sha = require('crypto').createHash('sha256').update(buf).digest('hex')
  const nome = `snap-${cam.nome.replace(/[^\w]+/g, '_')}-${Date.now()}.png`
  fs.writeFileSync(path.join(MEDIA_DIR, 'midia', nome), buf)
  store.custodia(nome, sha)
  store.registrarEvento('snapshot', cam.nome, `Snapshot salvo: ${nome} (SHA-256 ${sha.slice(0, 12)}…)`, 'info')
  mostraBanner(`📷 Snapshot salvo em Documentos/VigiaCam/midia/${nome}`, 'info')
}

// ---------- Gravação de vídeo ----------
function toggleGravacao(video, cam, btn) {
  const ativo = state.gravando[cam.url]
  if (ativo) {
    ativo.stop()
    delete state.gravando[cam.url]
    btn.classList.remove('rec-on')
    return
  }
  if (!video.videoWidth) return
  const stream = video.captureStream()
  const rec = new MediaRecorder(stream, { mimeType: 'video/webm;codecs=vp9' })
  const chunks = []
  rec.ondataavailable = e => chunks.push(e.data)
  rec.onstop = async () => {
    const buf = Buffer.from(await new Blob(chunks).arrayBuffer())
    const sha = require('crypto').createHash('sha256').update(buf).digest('hex')
    const nome = `rec-${cam.nome.replace(/[^\w]+/g, '_')}-${Date.now()}.webm`
    fs.writeFileSync(path.join(MEDIA_DIR, 'midia', nome), buf)
    store.custodia(nome, sha)
    store.registrarEvento('gravacao', cam.nome, `Gravação salva: ${nome} (SHA-256 ${sha.slice(0, 12)}…)`, 'info')
    mostraBanner(`⏺ Gravação salva em Documentos/VigiaCam/midia/${nome}`, 'info')
  }
  rec.start(1000)
  state.gravando[cam.url] = rec
  btn.classList.add('rec-on')
  store.registrarEvento('gravacao', cam.nome, 'Gravação iniciada', 'info')
}

// ---------- Detecção + rastreamento (SORT-lite com IDs) ----------
const tracks = {}   // camUrl -> [{id,cx,cy,cls,idade}]
let proximoId = 1

function rastreia(cam, dets) {
  const ts = tracks[cam.url] || (tracks[cam.url] = [])
  ts.forEach(t => t.idade++)
  for (const d of dets) {
    const cx = d.x + d.w / 2, cy = d.y + d.h / 2
    let melhor = null, melhorDist = Math.max(d.w, d.h) * 1.2
    for (const t of ts) {
      if (t.cls !== d.cls) continue
      const dist = Math.hypot(t.cx - cx, t.cy - cy)
      if (dist < melhorDist) { melhor = t; melhorDist = dist }
    }
    if (melhor) { melhor.cx = cx; melhor.cy = cy; melhor.idade = 0; d.id = melhor.id }
    else { const id = proximoId++; ts.push({ id, cx, cy, cls: d.cls, idade: 0 }); d.id = id }
  }
  tracks[cam.url] = ts.filter(t => t.idade < 30)
}

function iniciaDeteccao(video, overlay, card, cam) {
  const cfg = store.config
  let frames = 0
  const fpsEl = card.querySelector('.fps')
  const fpsTimer = setInterval(() => { fpsEl.textContent = `${frames} fps`; frames = 0 }, 1000)
  return setInterval(async () => {
    if (video.readyState < 2 || document.hidden) return
    let dets = []
    if (cfg.deteccao) {
      dets = await Detector.detect(video, cfg.confianca, null) || []
      frames++
      rastreia(cam, dets)
      avaliaAlarmes(dets, cam)
      state.contagens[cam.nome] = dets
    }
    desenha(overlay, video, dets, cam)
  }, Math.max(66, 1000 / cfg.fpsMax))
}

function desenha(overlay, video, dets, cam) {
  const w = overlay.clientWidth, h = overlay.clientHeight
  if (!w) return
  if (overlay.width !== w) overlay.width = w
  if (overlay.height !== h) overlay.height = h
  const ctx = overlay.getContext('2d')
  ctx.clearRect(0, 0, w, h)
  const vw = video.videoWidth, vh = video.videoHeight
  if (vw) {
    const scale = Math.max(w / vw, h / vh)
    const ox = (w - vw * scale) / 2, oy = (h - vh * scale) / 2
    ctx.font = 'bold 10px Segoe UI'
    for (const d of dets) {
      const x = d.x * scale + ox, y = d.y * scale + oy, bw = d.w * scale, bh = d.h * scale
      const cor = d.cls === 'person' ? '#ff453a' : d.cls === 'truck' ? '#29b6f6' : '#f25c1a'
      ctx.strokeStyle = cor; ctx.lineWidth = 1.5
      ctx.strokeRect(x, y, bw, bh)
      const label = `${d.label} #${d.id} ${Math.round(d.score * 100)}%`
      const tw = ctx.measureText(label).width + 8
      ctx.fillStyle = cor; ctx.fillRect(x, y - 14, tw, 14)
      ctx.fillStyle = '#fff'; ctx.fillText(label, x + 4, y - 4)
    }
  }
  desenhaZonas(ctx, w, h, cam)
}

// ---------- Alarmes (som + webhook) ----------
let ultimoAlarme = 0
function avaliaAlarmes(dets, cam) {
  const agora = Date.now()
  if (agora - ultimoAlarme < 15000) return
  for (const regra of store.alarmes) {
    if (!regra.ativo) continue
    const n = dets.filter(d => d.cls === regra.classe).length
    if (n >= regra.limite) {
      ultimoAlarme = agora
      const label = Detector.CLASS_PT[regra.classe] || regra.classe
      mostraBanner(`${regra.nome} — ${n} ${label} em ${cam.nome}`, regra.severidade)
      store.registrarEvento('alarme', cam.nome, `${regra.nome}: ${n}× ${regra.classe}`, regra.severidade)
      if (store.config.som) somAlarme(regra.severidade)
      dispararWebhook({ regra: regra.nome, severidade: regra.severidade, camera: cam.nome, contagem: n, classe: regra.classe, ts: new Date().toISOString() })
      return
    }
  }
}

function somAlarme(sev) {
  try {
    const ac = new AudioContext()
    const osc = ac.createOscillator(), g = ac.createGain()
    osc.connect(g); g.connect(ac.destination)
    osc.frequency.value = sev === 'critico' ? 880 : 620
    g.gain.setValueAtTime(0.15, ac.currentTime)
    g.gain.exponentialRampToValueAtTime(0.001, ac.currentTime + 0.6)
    osc.start(); osc.stop(ac.currentTime + 0.6)
  } catch (e) {}
}

function dispararWebhook(payload) {
  const url = store.config.webhook
  if (!url || !url.startsWith('http')) return
  fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) })
    .catch(e => console.error('webhook:', e.message))
}

function mostraBanner(msg, sev) {
  const b = document.getElementById('alarm-banner')
  b.className = `sev-${sev}`
  b.innerHTML = `🔔 ${msg}<span class="tag">${sev === 'critico' ? 'CRÍTICO' : sev === 'aviso' ? 'AVISO' : 'INFORMATIVO'}</span>`
  clearTimeout(b._t)
  b._t = setTimeout(() => b.classList.add('hidden'), 8000)
}

function renderAlarms(el) {
  const rows = store.alarmes.map((a, i) => `
    <div class="list-row">
      <input type="checkbox" ${a.ativo ? 'checked' : ''} data-i="${i}" class="al-toggle">
      <div style="flex:1">
        <div style="font-weight:700">${a.nome}</div>
        <div class="muted">≥ ${a.limite}× ${a.classe}</div>
      </div>
      <span class="badge ${a.severidade}">${a.severidade.toUpperCase()}</span>
      <button class="btn danger al-del" data-i="${i}">Remover</button>
    </div>`).join('')
  el.innerHTML = `<div class="page"><h2>Regras de Alarme</h2>${rows}
    <div class="form-grid">
      <input type="text" id="al-nome" placeholder="Nome da regra">
      <select id="al-classe">${Detector.COCO_CLASSES.slice(0, 10).map(c => `<option value="${c}">${Detector.CLASS_PT[c] || c}</option>`).join('')}</select>
      <input type="text" id="al-limite" placeholder="Limite (nº de objetos)">
      <select id="al-sev"><option value="info">Informativo</option><option value="aviso">Aviso</option><option value="critico">Crítico</option></select>
      <button class="btn" id="al-add">Adicionar regra</button>
    </div></div>`
  el.querySelectorAll('.al-toggle').forEach(t => t.onchange = () => {
    const v = store.alarmes; v[t.dataset.i].ativo = t.checked; store.alarmes = v
  })
  el.querySelectorAll('.al-del').forEach(b => b.onclick = () => {
    const v = store.alarmes; v.splice(b.dataset.i, 1); store.alarmes = v; render()
  })
  el.querySelector('#al-add').onclick = () => {
    const nome = el.querySelector('#al-nome').value.trim()
    const limite = parseInt(el.querySelector('#al-limite').value)
    if (!nome || !limite) return
    const v = store.alarmes
    v.push({ nome, classe: el.querySelector('#al-classe').value, limite, severidade: el.querySelector('#al-sev').value, ativo: true })
    store.alarmes = v; render()
  }
}

// ---------- Negócio / Dashboard / Eventos / Relatórios / Config ----------
function renderBusiness(el) {
  const tot = {}
  Object.values(state.contagens).flat().forEach(d => tot[d.label] = (tot[d.label] || 0) + 1)
  const kpis = Object.entries(tot).sort((a, b) => b[1] - a[1]).slice(0, 8)
  el.innerHTML = `<div class="page"><h2>Analíticos de Negócio</h2>
    <div class="kpi-grid">${kpis.map(([k, v]) =>
      `<div class="kpi"><div class="kpi-title">${k} em cena (agora)</div><div class="kpi-value">${v}</div></div>`).join('') ||
      '<div class="empty">Sem detecções no momento</div>'}</div></div>`
}

function fmtUptime(ms) {
  const m = Math.floor(ms / 60000)
  return m < 60 ? `${m}min` : `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}`
}

function renderDashboard(el) {
  const evHoje = store.eventos.filter(e => new Date(e.ts).toDateString() === new Date().toDateString())
  const saudeRows = store.cameras.filter(c => state.saude[c.url]).map(c => {
    const s = state.saude[c.url]
    const on = state.online.has(c.url)
    return `<div class="list-row">
      <span class="badge ${on ? 'ok' : 'critico'}">${on ? 'ONLINE' : 'OFFLINE'}</span>
      <div style="flex:1"><div style="font-weight:700">${c.nome}</div>
      <div class="muted">${on ? `no ar há ${fmtUptime(Date.now() - s.desdeTs)}` : 'sem sinal'} · ${s.reconexoes} reconexões na sessão</div></div>
    </div>`
  }).join('')
  el.innerHTML = `<div class="page"><h2>Dashboard</h2>
    <div class="kpi-grid">
      <div class="kpi"><div class="kpi-title">Câmeras</div><div class="kpi-value">${store.cameras.length}</div></div>
      <div class="kpi"><div class="kpi-title">Online</div><div class="kpi-value" style="color:var(--ok)">${state.online.size}</div></div>
      <div class="kpi"><div class="kpi-title">Eventos Hoje</div><div class="kpi-value" style="color:var(--accent2)">${evHoje.length}</div></div>
      <div class="kpi"><div class="kpi-title">Regras de Alarme</div><div class="kpi-value" style="color:var(--accent)">${store.alarmes.filter(a => a.ativo).length}</div></div>
    </div>
    <h2>Saúde das Câmeras</h2>
    ${saudeRows || '<div class="empty">Abra o Ao Vivo para coletar métricas de saúde</div>'}
    <h2 style="margin-top:18px">Eventos Recentes</h2>
    ${store.eventos.slice(0, 10).map(linhaEvento).join('') || '<div class="empty">⚡ Nenhum evento registrado</div>'}</div>`
}

function linhaEvento(e) {
  return `<div class="list-row"><span class="badge ${e.severidade || 'info'}">${(e.severidade || 'info').toUpperCase()}</span>
    <div style="flex:1"><div style="font-weight:700">${e.detalhe}</div><div class="muted">${e.camera}</div></div>
    <span class="muted">${new Date(e.ts).toLocaleString('pt-BR')}</span></div>`
}

function renderEvents(el) {
  el.innerHTML = `<div class="page"><h2>Eventos <button class="btn ghost" id="csv" style="float:right">⬇ Exportar CSV</button></h2>
    ${store.eventos.map(linhaEvento).join('') || '<div class="empty">⚡ Nenhum evento registrado</div>'}</div>`
  el.querySelector('#csv').onclick = () => {
    const csv = 'data,hora,tipo,severidade,camera,detalhe\n' + store.eventos.map(e => {
      const d = new Date(e.ts)
      return [d.toLocaleDateString('pt-BR'), d.toLocaleTimeString('pt-BR'), e.tipo, e.severidade || '', `"${e.camera}"`, `"${e.detalhe}"`].join(',')
    }).join('\n')
    const nome = `eventos-${new Date().toISOString().slice(0, 10)}.csv`
    fs.writeFileSync(path.join(MEDIA_DIR, nome), '﻿' + csv)
    mostraBanner(`⬇ CSV exportado para Documentos/VigiaCam/${nome}`, 'info')
  }
}

function renderReports(el) {
  el.innerHTML = `<div class="page"><h2>Relatórios</h2>
    <p style="font-size:12px;color:var(--muted);margin-bottom:14px">Gera um relatório dos eventos registrados (imprimível / salvável em PDF pelo diálogo do Windows).</p>
    <button class="btn" id="rep-gerar">Gerar relatório de eventos</button></div>`
  el.querySelector('#rep-gerar').onclick = () => {
    const w = window.open('', '_blank')
    w.document.write(`<html><head><title>Relatório VIGIA·CAM</title>
      <style>body{font-family:Segoe UI;padding:32px}h1{font-size:20px}td,th{border:1px solid #ccc;padding:6px;font-size:12px}table{border-collapse:collapse;width:100%}</style>
      </head><body><h1>VIGIA·CAM — Relatório de Eventos</h1>
      <p>Gerado em ${new Date().toLocaleString('pt-BR')} · ${store.cameras.length} câmeras · ${store.eventos.length} eventos</p>
      <table><tr><th>Data/hora</th><th>Severidade</th><th>Câmera</th><th>Detalhe</th></tr>
      ${store.eventos.map(e => `<tr><td>${new Date(e.ts).toLocaleString('pt-BR')}</td><td>${e.severidade || ''}</td><td>${e.camera}</td><td>${e.detalhe}</td></tr>`).join('')}
      </table><script>window.print()<\/script></body></html>`)
  }
}

function renderConfig(el) {
  const cfg = store.config
  const sub = state.cfgTab || 0
  const detTab = `
    <div class="cfg-row"><span>Detecção de objetos (YOLOv8n)</span>
      <input type="checkbox" id="cfg-det" ${cfg.deteccao ? 'checked' : ''}></div>
    <div class="cfg-row"><span>FPS Máximo de inferência</span>
      <span class="cfg-value">${cfg.fpsMax}</span><input type="range" id="cfg-fps" min="1" max="30" value="${cfg.fpsMax}"></div>
    <div class="cfg-row"><span>Confiança Mínima</span>
      <span class="cfg-value">${Math.round(cfg.confianca * 100)}%</span><input type="range" id="cfg-conf" min="5" max="95" step="5" value="${cfg.confianca * 100}"></div>
    <div class="cfg-row"><span>Som de alarme</span>
      <input type="checkbox" id="cfg-som" ${cfg.som ? 'checked' : ''}></div>
    <div class="cfg-row"><span>OSD (relógio nos tiles)</span>
      <input type="checkbox" id="cfg-osd" ${cfg.osd ? 'checked' : ''}></div>
    <div class="cfg-row"><span>Webhook de alarme (POST JSON)</span>
      <input type="text" id="cfg-webhook" placeholder="https://..." value="${cfg.webhook || ''}" style="width:280px"></div>`
  const camTab = `
    ${store.cameras.map((c, i) => `<div class="list-row"><div style="flex:1">
      <div style="font-weight:700">${c.nome}</div><div class="muted">${c.categoria} · ${c.url}</div></div>
      <button class="btn danger cam-del" data-i="${i}">Remover</button></div>`).join('')}
    <div class="form-grid">
      <input type="text" id="cam-nome" placeholder="Nome da câmera">
      <input type="text" id="cam-cat" placeholder="Categoria">
      <input type="text" id="cam-url" placeholder="URL HLS (.m3u8)">
      <button class="btn" id="cam-add">Adicionar câmera</button>
      <button class="btn ghost" id="cam-reset">Restaurar câmeras padrão</button>
    </div>`
  el.innerHTML = `<div class="page"><div class="seg">
      <button class="${sub === 0 ? 'active' : ''}" data-s="0">Detecção</button>
      <button class="${sub === 1 ? 'active' : ''}" data-s="1">Câmeras</button></div>
    ${sub === 0 ? detTab : camTab}</div>`
  el.querySelectorAll('.seg button').forEach(b => b.onclick = () => { state.cfgTab = +b.dataset.s; render() })
  if (sub === 0) {
    const upd = (k, v) => { const c = store.config; c[k] = v; store.config = c }
    el.querySelector('#cfg-det').onchange = e => { upd('deteccao', e.target.checked); render() }
    el.querySelector('#cfg-fps').onchange = e => { upd('fpsMax', +e.target.value); render() }
    el.querySelector('#cfg-conf').onchange = e => { upd('confianca', e.target.value / 100); render() }
    el.querySelector('#cfg-som').onchange = e => upd('som', e.target.checked)
    el.querySelector('#cfg-osd').onchange = e => upd('osd', e.target.checked)
    el.querySelector('#cfg-webhook').onchange = e => upd('webhook', e.target.value.trim())
  } else {
    el.querySelectorAll('.cam-del').forEach(b => b.onclick = () => {
      const v = store.cameras; v.splice(b.dataset.i, 1); store.cameras = v; render()
    })
    el.querySelector('#cam-add').onclick = () => {
      const nome = el.querySelector('#cam-nome').value.trim(), url = el.querySelector('#cam-url').value.trim()
      if (!nome || !url.startsWith('http')) return
      const v = store.cameras
      v.push({ nome, categoria: el.querySelector('#cam-cat').value.trim() || 'Geral', url })
      store.cameras = v; render()
    }
    el.querySelector('#cam-reset').onclick = () => { store.cameras = CAMERAS_SEED.slice(); render() }
  }
}

// ---------- Atalhos de teclado ----------
document.addEventListener('keydown', e => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT') return
  if (state.tab !== 'cameras') return
  if (e.key >= '1' && e.key <= '4') { state.grid = +e.key; state.foco = null; render() }
  else if (e.key === 'ArrowLeft') { state.pagina = Math.max(0, state.pagina - 1); render() }
  else if (e.key === 'ArrowRight') { state.pagina++; render() }
  else if (e.key.toLowerCase() === 'r') { state.ronda = !state.ronda; render() }
  else if (e.key === 'Escape' && state.foco) { state.foco = null; state.editZonas = false; render() }
})

// ---------- Loop principal ----------
function destroyPlayers() {
  clearTimeout(state.rondaTimer)
  state.players.forEach(p => {
    clearInterval(p.timer); clearInterval(p.clockTimer)
    try { p.hls.destroy() } catch (e) {}
  })
  state.players = []
}

function render() {
  renderNav()
  const el = document.getElementById('detail')
  destroyPlayers()
  switch (state.tab) {
    case 'cameras': renderLive(el); break
    case 'alarms': renderAlarms(el); break
    case 'business': renderBusiness(el); break
    case 'dashboard': renderDashboard(el); break
    case 'events': renderEvents(el); break
    case 'reports': renderReports(el); break
    case 'config': renderConfig(el); break
  }
}

render()
setInterval(() => { if (state.tab === 'dashboard' || state.tab === 'business') render() }, 5000)
