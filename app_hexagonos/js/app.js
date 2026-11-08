const PARAMS = [
  ["ta_inc", "Incubación", "Tasa de incubación. El periodo medio es 4 días."],
  ["ta_mor", "Mortalidad", "Mortalidad por PPA. La enfermedad dura unos 6 días."],
  ["ta_rec", "Recuperación", "Tasa de recuperación. Sobrevive cerca del 5 %."],
  ["ta_des", "Descomposición", "Descomposición de carcasas. Persisten unos 30 días."],
  ["con_vi", "Contagio vivos", "Contagio por contacto directo con jabalíes vivos."],
  ["con_ca", "Contagio carcasas", "Contagio ambiental por carcasas en el terreno."],
  ["kappa", "Acoplamiento", "Fracción de la fuerza de infección que cruza al vecino."],
  ["pamp_d", "Agente a medio, producción", "Probabilidad de que un agente en producción contagie el medio."],
  ["pamc_d", "Agente a medio, clausura", "Probabilidad de que un agente clausurado contagie el medio."],
  ["pavp_d", "Agente a vehículo, producción", "Probabilidad de que un agente en producción contagie un vehículo."],
  ["pavc_d", "Agente a vehículo, clausura", "Probabilidad de que un agente clausurado contagie un vehículo."],
  ["pmap_d", "Medio a agente", "Probabilidad de que el medio contagie a un agente en producción."],
  ["pvap_d", "Vehículo a agente", "Probabilidad de que un vehículo contagie a un agente en producción."],
  ["ND", "Diagonal", "Número de hexágonos en la diagonal principal. El mapa es ND por ND.", "number"],
  ["RH", "Radio", "Distancia del centro de cada hexágono a un vértice, en km.", "number"],
  ["CCONT", "Columnas control", "Columnas, separadas por comas, donde todos los hexágonos empiezan con la densidad de control.", "text"],
  ["Smin", "Densidad mínima", "Mínimo de la densidad aleatoria de susceptibles, fuera de las columnas de control.", "number"],
  ["Smax", "Densidad máxima", "Máximo de la densidad aleatoria de susceptibles, fuera de las columnas de control.", "number"],
  ["Scon", "Densidad control", "Densidad inicial de susceptibles en las columnas de control.", "number"]
];

const COLUMNAS_HEX = ["idh", "c", "f", "q", "r", "x", "y", "dia", "S", "E", "I", "R", "C"];
const DENSIDADES = ["S", "E", "I", "R", "C"];

const estado = {
  hexagonos: [],
  conexiones: [],
  dhd: null,
  dc: null,
  porDia: null,
  dia: 0,
  timer: null,
  pagDhd: 0,
  pagDc: 0
};

const $ = (id) => document.getElementById(id);

function filas(columnas) {
  if (!columnas) return [];
  const claves = Object.keys(columnas);
  if (!claves.length || !columnas[claves[0]]) return [];
  const n = columnas[claves[0]].length;
  const salida = [];
  for (let i = 0; i < n; i++) {
    const fila = {};
    for (const k of claves) fila[k] = columnas[k][i];
    salida.push(fila);
  }
  return salida;
}

function columnasDe(filasTabla) {
  const salida = {};
  if (!filasTabla.length) return salida;
  for (const k of Object.keys(filasTabla[0])) salida[k] = [];
  for (const fila of filasTabla) {
    for (const k of Object.keys(salida)) salida[k].push(fila[k]);
  }
  return salida;
}

function paramsDesdeFormulario() {
  const p = {};
  for (const [simbolo, , , tipo] of PARAMS) {
    const valor = $("p-" + simbolo).value;
    p[simbolo] = tipo === "text" ? valor : Number(valor);
  }
  return p;
}

function pintarParametros(valores) {
  $("params").innerHTML = PARAMS.map(([simbolo, nombre, ayuda, tipo]) => `
    <div class="field">
      <label>${nombre} <span class="sym">(${simbolo})</span>
        <span class="ayuda" tabindex="0">?<span class="globo">${ayuda}</span></span>
      </label>
      <input id="p-${simbolo}" type="${tipo === "text" ? "text" : "number"}" step="any" value="${valores[simbolo]}" />
    </div>`).join("");
}

function listaNumeros(texto) {
  const partes = String(texto || "").split(/[,;\s]+/).filter(Boolean);
  if (!partes.length) return null;
  return partes.map(Number).filter((n) => Number.isFinite(n));
}

function evaluar(formula, fila) {
  const expr = String(formula || "S").replace(/\s+/g, "");
  if (!expr) return Number(fila.S) || 0;
  if (!/^[SEIRC0-9+\-*/().]+$/.test(expr)) {
    throw new Error("La fórmula solo puede usar S, E, I, R, C y + - * / ( ).");
  }
  const js = expr.replace(/[SEIRC]/g, (letra) => `(${Number(fila[letra]) || 0})`);
  const valor = Function(`"use strict"; return (${js});`)();
  if (!Number.isFinite(valor)) throw new Error("La fórmula no da un número.");
  return valor;
}

function colorDe(valor) {
  const t = Math.max(0, Math.min(1, valor / 15));
  const r = Math.round(255 + (155 - 255) * t);
  const g = Math.round(255 * (1 - t));
  const b = Math.round(255 * (1 - t));
  return `rgb(${r},${g},${b})`;
}

function csvDe(filasTabla) {
  if (!filasTabla.length) return "";
  const claves = Object.keys(filasTabla[0]);
  const lineas = [claves.join(",")];
  for (const fila of filasTabla) {
    lineas.push(claves.map((k) => fila[k]).join(","));
  }
  return lineas.join("\n");
}

function descargar(nombre, texto) {
  const blob = new Blob([texto], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = nombre;
  a.click();
  URL.revokeObjectURL(url);
}

function descargarJson(nombre, objeto) {
  descargar(nombre, JSON.stringify(objeto, null, 2));
}

function tablaEditable(id, filasTabla, columnas, alCambiar) {
  const tabla = $(id);
  const cabeza = "<tr>" + columnas.map((c) => `<th>${c}</th>`).join("") + "</tr>";
  const cuerpo = filasTabla.map((fila, i) => {
    const celdas = columnas.map((c) =>
      `<td><input data-i="${i}" data-c="${c}" value="${fila[c] ?? ""}" /></td>`
    ).join("");
    return `<tr>${celdas}</tr>`;
  }).join("");
  tabla.innerHTML = cabeza + cuerpo;
  tabla.oninput = (evento) => {
    const input = evento.target;
    if (!input.dataset) return;
    const i = Number(input.dataset.i);
    const clave = input.dataset.c;
    const numero = Number(input.value);
    filasTabla[i][clave] = Number.isFinite(numero) && input.value !== "" ? numero : input.value;
    alCambiar();
  };
}

function invalidarSimulacion() {
  parar();
  estado.dhd = null;
  estado.dc = null;
  estado.porDia = null;
  $("estado-sim").textContent = "El mapa cambió. Play volverá a calcular la simulación.";
}

function leerTablaHex() {
  return estado.hexagonos;
}

function diaActualFilas() {
  if (!estado.porDia || !estado.porDia.has(estado.dia)) return estado.hexagonos.map((h) => ({ ...h }));
  return estado.porDia.get(estado.dia).map((fila) => {
    const base = estado.hexagonos.find((h) => Number(h.idh) === Number(fila.idh)) || {};
    return { ...base, ...fila };
  });
}

function pintarTablasMapa() {
  tablaEditable("tabla-hex", diaActualFilas(), COLUMNAS_HEX, () => {
    const mostradas = diaActualFilas();
    const inputs = $("tabla-hex").querySelectorAll("input");
    inputs.forEach((input) => {
      const i = Number(input.dataset.i);
      const clave = input.dataset.c;
      const valor = input.value === "" ? "" : (Number.isFinite(Number(input.value)) ? Number(input.value) : input.value);
      mostradas[i][clave] = valor;
      if (estado.dia === 0 || !DENSIDADES.includes(clave)) {
        const idh = Number(mostradas[i].idh);
        const destino = estado.hexagonos.find((h) => Number(h.idh) === idh);
        if (destino && clave in destino) destino[clave] = valor;
      }
    });
    if (estado.dia === 0) invalidarSimulacion();
    dibujarMapa();
  });
  tablaEditable("tabla-con", estado.conexiones, ["idh", "pos", "idhv"], invalidarSimulacion);
}

function indexarDias() {
  const mapa = new Map();
  const dias = estado.dhd.dia;
  for (let i = 0; i < dias.length; i++) {
    const d = Number(dias[i]);
    if (!mapa.has(d)) mapa.set(d, []);
    const fila = {};
    for (const k of Object.keys(estado.dhd)) fila[k] = estado.dhd[k][i];
    mapa.get(d).push(fila);
  }
  estado.porDia = mapa;
  const maximo = Math.max(...dias.map(Number));
  $("slider-dia").max = String(maximo);
  $("diaf").value = String(maximo);
  $("diai").value = "0";
}

function fijarDia(dia, redibujarTabla = true) {
  const maximo = Number($("slider-dia").max) || 0;
  estado.dia = Math.max(0, Math.min(maximo, Number(dia) || 0));
  $("slider-dia").value = String(estado.dia);
  $("slider-val").textContent = String(estado.dia);
  $("dia-num").value = String(estado.dia);
  if (!estado.timer && estado.dhd) {
    $("estado-sim").textContent = `Día ${estado.dia} de ${maximo}`;
  }
  dibujarMapa();
  if (redibujarTabla && $("tabla-hex").querySelector("input") !== document.activeElement) {
    pintarTablasMapa();
  }
}

function dibujarMapa() {
  const canvas = $("lienzo");
  const ctx = canvas.getContext("2d");
  const radio = Number($("p-RH").value) || 1;
  const formula = $("formula-mapa").value;
  const filasDia = (estado.porDia && estado.porDia.get(estado.dia)) || estado.hexagonos;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = "#0c120b";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  if (!filasDia.length) return;

  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const h of filasDia) {
    minX = Math.min(minX, Number(h.x) - radio);
    maxX = Math.max(maxX, Number(h.x) + radio);
    minY = Math.min(minY, Number(h.y) - radio);
    maxY = Math.max(maxY, Number(h.y) + radio);
  }
  const pad = 28;
  const escala = Math.min(
    (canvas.width - 2 * pad) / (maxX - minX || 1),
    (canvas.height - 2 * pad) / (maxY - minY || 1)
  );
  const X = (x) => pad + (x - minX) * escala;
  const Y = (y) => canvas.height - pad - (y - minY) * escala;
  const rpx = radio * escala;
  let maximo = 0;
  let error = "";

  for (const h of filasDia) {
    let valor = 0;
    try { valor = evaluar(formula, h); }
    catch (e) { error = e.message; valor = 0; }
    maximo = Math.max(maximo, valor);
    const cx = Number(h.x);
    const cy = Number(h.y);
    ctx.beginPath();
    for (let k = 0; k < 6; k++) {
      const pos = Math.PI / 6 + k * Math.PI / 3;
      const vx = X(cx + Math.sin(pos) * radio);
      const vy = Y(cy + Math.cos(pos) * radio);
      if (k === 0) ctx.moveTo(vx, vy);
      else ctx.lineTo(vx, vy);
    }
    ctx.closePath();
    ctx.fillStyle = colorDe(valor);
    ctx.fill();
    ctx.strokeStyle = "#6d7a62";
    ctx.lineWidth = 1;
    ctx.stroke();
    if (rpx > 22) {
      ctx.fillStyle = "#1b1b1b";
      ctx.font = "11px ui-monospace, monospace";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(String(h.idh), X(cx), Y(cy));
    }
  }
  $("max-formula").textContent = error ? error : `máx ${maximo.toFixed(3)}`;
  $("texto-mapa").textContent = $("nota-mapa").value;
}

function dibujarSerie() {
  const canvas = $("grafico");
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = "#0c120b";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  $("texto-serie").textContent = $("nota-serie").value;
  if (!estado.dhd) {
    ctx.fillStyle = "#8aa078";
    ctx.font = "16px ui-monospace, monospace";
    ctx.fillText("Todavía no hay simulación.", 24, 40);
    return;
  }
  const d0 = Number($("diai").value) || 0;
  const d1 = Number($("diaf").value);
  const formula = $("formula-serie").value;
  const columnas = listaNumeros($("filtro-c").value);
  const filasFiltro = listaNumeros($("filtro-f").value);
  const series = new Map();
  let minY = Infinity, maxY = -Infinity;
  try {
    for (const [dia, grupo] of estado.porDia) {
      if (dia < d0 || dia > d1) continue;
      for (const fila of grupo) {
        if (columnas && !columnas.includes(Number(fila.c))) continue;
        if (filasFiltro && !filasFiltro.includes(Number(fila.f))) continue;
        const valor = evaluar(formula, fila);
        minY = Math.min(minY, valor);
        maxY = Math.max(maxY, valor);
        const clave = String(fila.idh);
        if (!series.has(clave)) series.set(clave, { c: Number(fila.c), puntos: [] });
        series.get(clave).puntos.push([dia, valor]);
      }
    }
  } catch (e) {
    $("texto-serie").textContent = e.message;
    return;
  }
  if (!series.size) return;
  if (minY === maxY) { minY -= 1; maxY += 1; }
  const izq = 54, der = 16, arriba = 16, abajo = 36;
  const ancho = canvas.width - izq - der;
  const alto = canvas.height - arriba - abajo;
  const xDe = (d) => izq + ((d - d0) / (d1 - d0 || 1)) * ancho;
  const yDe = (v) => arriba + (1 - (v - minY) / (maxY - minY)) * alto;
  const paleta = ["#7cff6b", "#ffd000", "#ff4d2e", "#3ec6ff", "#c5a572", "#e9c46a", "#f4a261", "#b5179e", "#90e0ef", "#ffffff"];

  ctx.strokeStyle = "#3d5a32";
  ctx.beginPath();
  ctx.moveTo(izq, arriba);
  ctx.lineTo(izq, arriba + alto);
  ctx.lineTo(izq + ancho, arriba + alto);
  ctx.stroke();
  ctx.fillStyle = "#8aa078";
  ctx.font = "12px ui-monospace, monospace";
  ctx.fillText(maxY.toFixed(2), 6, arriba + 10);
  ctx.fillText(minY.toFixed(2), 6, arriba + alto);
  ctx.fillText(String(d0), izq, canvas.height - 12);
  ctx.fillText(String(d1), izq + ancho - 24, canvas.height - 12);

  for (const serie of series.values()) {
    ctx.beginPath();
    ctx.strokeStyle = paleta[Math.abs(serie.c) % paleta.length];
    serie.puntos.forEach(([d, v], i) => {
      const x = xDe(d);
      const y = yDe(v);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  }
}

function parar() {
  if (estado.timer) clearInterval(estado.timer);
  estado.timer = null;
  $("btn-play").textContent = "▶ PLAY";
  $("btn-play").classList.remove("activo");
}

function pasoVisible() {
  return Math.max(1, Number($("cada").value) || 1);
}

function arrancarReloj(hastaElFinal) {
  parar();
  $("btn-play").textContent = "❚❚ PAUSA";
  $("btn-play").classList.add("activo");
  const maximo = Number($("slider-dia").max) || 0;
  estado.timer = setInterval(() => {
    const siguiente = estado.dia + pasoVisible();
    if (siguiente > maximo) {
      fijarDia(maximo);
      parar();
      $("estado-sim").textContent = "Secuencia terminada.";
      return;
    }
    fijarDia(siguiente);
    $("estado-sim").textContent = `Día ${estado.dia} de ${maximo}`;
  }, 450);
  if (!hastaElFinal && false) return;
}

async function asegurarSimulacion() {
  if (estado.dhd) return;
  $("estado-sim").textContent = "Calculando la simulación…";
  const cuerpo = {
    params: paramsDesdeFormulario(),
    hexagonos: estado.hexagonos,
    conexiones: estado.conexiones,
    dias: Number($("dias").value) || 365,
    semilla: Number($("semilla").value) || 1
  };
  const respuesta = await fetch("/simular", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(cuerpo)
  });
  const datos = await respuesta.json();
  if (!respuesta.ok || datos.error) throw new Error(datos.error || "La simulación falló");
  estado.dhd = datos.dhd;
  estado.dc = datos.dc;
  indexarDias();
  estado.pagDhd = 0;
  estado.pagDc = 0;
  pintarResultados();
  $("estado-sim").textContent = `Simulación lista. Último día guardado: ${datos.dias}.`;
}

function pagina(filasTabla, n, contenedor, tablaId) {
  const tam = 40;
  const paginas = Math.max(1, Math.ceil(filasTabla.length / tam));
  const paginaActual = Math.min(n, paginas - 1);
  const corte = filasTabla.slice(paginaActual * tam, paginaActual * tam + tam);
  const claves = filasTabla.length ? Object.keys(filasTabla[0]) : [];
  $(tablaId).innerHTML = "<tr>" + claves.map((c) => `<th>${c}</th>`).join("") + "</tr>" +
    corte.map((fila) => "<tr>" + claves.map((c) => `<td>${fila[c]}</td>`).join("") + "</tr>").join("");
  $(contenedor).innerHTML = "";
  const info = document.createElement("span");
  info.textContent = `${filasTabla.length} filas · página ${paginaActual + 1} / ${paginas}`;
  const prev = document.createElement("button");
  prev.textContent = "ANTERIOR";
  const next = document.createElement("button");
  next.textContent = "SIGUIENTE";
  prev.onclick = () => pagina(filasTabla, paginaActual - 1, contenedor, tablaId);
  next.onclick = () => pagina(filasTabla, paginaActual + 1, contenedor, tablaId);
  $(contenedor).append(prev, info, next);
  return paginaActual;
}

function pintarResultados() {
  const dhd = filas(estado.dhd);
  const dc = filas(estado.dc);
  estado.pagDhd = pagina(dhd, estado.pagDhd, "pag-dhd", "tabla-dhd");
  estado.pagDc = pagina(dc, estado.pagDc, "pag-dc", "tabla-dc");
}

function aplicarMapa(datos, aviso) {
  estado.hexagonos = filas(datos.hexagonos);
  estado.conexiones = filas(datos.conexiones);
  estado.dhd = null;
  estado.dc = null;
  estado.porDia = null;
  estado.dia = 0;
  $("slider-dia").max = "0";
  fijarDia(0, false);
  pintarTablasMapa();
  $("aviso-mapa").textContent = aviso;
  $("estado-sim").textContent = estado.hexagonos.length
    ? "Mapa listo. Pulsa play para simular."
    : "Sin hexágonos.";
  dibujarMapa();
}

async function generarMapa() {
  parar();
  const q = new URLSearchParams({
    nd: $("p-ND").value,
    radio: $("p-RH").value,
    semilla: $("semilla").value,
    smin: $("p-Smin").value,
    smax: $("p-Smax").value,
    ccont: $("p-CCONT").value,
    scon: $("p-Scon").value,
    c0: "2",
    f0: "3"
  });
  $("aviso-mapa").textContent = "Generando mapa…";
  const respuesta = await fetch("/generar?" + q.toString());
  const datos = await respuesta.json();
  if (!respuesta.ok || datos.error) throw new Error(datos.error || "No se pudo generar el mapa");
  aplicarMapa(datos, `Mapa generado. ${filas(datos.hexagonos).length} hexágonos. Columnas de control: ${$("p-CCONT").value || "ninguna"}.`);
}

async function cargarMapa() {
  parar();
  $("aviso-mapa").textContent = "Leyendo agentes.json…";
  const respuesta = await fetch("/mapa");
  const datos = await respuesta.json();
  if (!respuesta.ok || datos.error) throw new Error(datos.error || "No se pudo cargar el mapa");
  const aviso = datos.aviso || `Mapa leído de agentes.json. ${filas(datos.hexagonos).length} hexágonos.`;
  aplicarMapa(datos, aviso);
}

function activarPestanas() {
  document.querySelectorAll(".tab").forEach((boton) => {
    boton.onclick = () => {
      document.querySelectorAll(".tab").forEach((b) => b.classList.remove("active"));
      document.querySelectorAll(".panel").forEach((p) => p.classList.remove("active"));
      boton.classList.add("active");
      $("panel-" + boton.dataset.tab).classList.add("active");
      if (boton.dataset.tab === "simulacion") dibujarMapa();
      if (boton.dataset.tab === "analisis") dibujarSerie();
      if (boton.dataset.tab === "resultados") pintarResultados();
    };
  });
}

async function guardar() {
  const params = paramsDesdeFormulario();
  const conexiones = estado.conexiones;
  descargarJson("parametros.json", params);
  descargarJson("conexiones.json", conexiones);
  const respuesta = await fetch("/guardar", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ params, conexiones })
  });
  const datos = await respuesta.json();
  if (!respuesta.ok || datos.error) throw new Error(datos.error || "No se guardó en el servidor");
  $("aviso-mapa").textContent = "Parámetros y conexiones guardados en el navegador y en app_hexagonos/salidas/.";
}

async function iniciar() {
  activarPestanas();
  const respuesta = await fetch("/parametros");
  const datos = await respuesta.json();
  pintarParametros(datos.params);
  $("btn-generar").onclick = () => generarMapa().catch((e) => { $("aviso-mapa").textContent = e.message; });
  $("btn-cargar").onclick = () => cargarMapa().catch((e) => { $("aviso-mapa").textContent = e.message; });
  $("btn-guardar").onclick = () => guardar().catch((e) => { $("aviso-mapa").textContent = e.message; });
  $("csv-hex").onclick = () => descargar("hexagonos.csv", csvDe(diaActualFilas()));
  $("csv-con").onclick = () => descargar("conexiones.csv", csvDe(estado.conexiones));
  $("csv-dhd").onclick = () => descargar("dhd.csv", csvDe(filas(estado.dhd)));
  $("csv-dc").onclick = () => descargar("dc.csv", csvDe(filas(estado.dc)));
  $("btn-conexion").onclick = () => {
    estado.conexiones.push({ idh: 1, pos: "N", idhv: 2 });
    invalidarSimulacion();
    pintarTablasMapa();
  };
  $("btn-formula").onclick = dibujarMapa;
  $("btn-serie").onclick = dibujarSerie;
  $("slider-dia").oninput = () => fijarDia($("slider-dia").value);
  $("dia-num").onchange = () => fijarDia($("dia-num").value);
  $("btn-play").onclick = async () => {
    if (estado.timer) { parar(); return; }
    try {
      await asegurarSimulacion();
      if (estado.dia >= Number($("slider-dia").max)) fijarDia(0);
      arrancarReloj();
    } catch (e) {
      $("estado-sim").textContent = e.message;
    }
  };
  $("btn-replay").onclick = async () => {
    try {
      await asegurarSimulacion();
      fijarDia(0);
      arrancarReloj();
    } catch (e) {
      $("estado-sim").textContent = e.message;
    }
  };
  dibujarMapa();
}

iniciar().catch((e) => {
  document.body.insertAdjacentHTML("beforeend", `<p class="status">${e.message}</p>`);
});
