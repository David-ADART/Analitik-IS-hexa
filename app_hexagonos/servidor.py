# servidor.py
# La misma app de hexágonos, con el motor en Python.
# Así puede alojarse en un servidor gratuito sin instalar R.
#
# Local:
#   HEXA_CLAVE='tu-clave' python3 servidor.py
# Luego abre http://127.0.0.1:8765/
#
# El azar usa el generador de Python. La misma semilla no reproduce
# los números de R, pero las ecuaciones son las del cuaderno.

import hmac
import json
import math
import os
import random
import secrets
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse


DIR = os.path.dirname(os.path.abspath(__file__))
RUTA_AGENTES = os.environ.get(
    "HEXA_AGENTES",
    os.path.normpath(os.path.join(DIR, "..", "datos", "agentes.json")),
)
RUTA_SALIDAS = os.path.join(DIR, "salidas")
CLAVE = os.environ.get("HEXA_CLAVE", "")
SESIONES = set()
ND_MAX = 40

PARAMETROS = {
    "ta_inc": 0.25,
    "ta_mor": 0.16,
    "ta_rec": 0.008,
    "ta_des": 0.033,
    "con_vi": 0.15,
    "con_ca": 0.10,
    "kappa": 0.05,
    "pamp_d": 0.1,
    "pamc_d": 0.05,
    "pavp_d": 0.8,
    "pavc_d": 0.1,
    "pmap_d": 0.1,
    "pvap_d": 0.8,
}

PARAMETROS_MAPA = {
    "ND": 10,
    "RH": 1,
    "CCONT": "4,7",
    "Smin": 4,
    "Smax": 10,
    "Scon": 0.5,
}

VECINOS = (
    ("NO", -1, 1),
    ("N", 0, 1),
    ("NE", 1, 0),
    ("SE", 1, -1),
    ("S", 0, -1),
    ("SO", -1, 0),
)

COLUMNAS_HEX = ("idh", "c", "f", "q", "r", "x", "y", "dia", "S", "E", "I", "R", "C")
COLUMNAS_DC = ("dia", "idh", "idhv", "prob", "cont")


def parametros_defecto():
    return dict(PARAMETROS)


def parametros_mapa():
    return dict(PARAMETROS_MAPA)


def completar_parametros(p):
    base = parametros_defecto()
    if not isinstance(p, dict):
        return base
    for nombre in base:
        if p.get(nombre) is None or p.get(nombre) == "":
            continue
        try:
            valor = float(p[nombre])
        except (TypeError, ValueError):
            continue
        if math.isnan(valor):
            continue
        base[nombre] = valor
    return base


def columnas_control(texto):
    if texto is None:
        return []
    if isinstance(texto, (int, float)) and not isinstance(texto, bool):
        return [int(texto)]
    if isinstance(texto, (list, tuple)):
        salida = []
        for parte in texto:
            try:
                salida.append(int(parte))
            except (TypeError, ValueError):
                continue
        return list(dict.fromkeys(salida))
    partes = str(texto).replace(";", ",").replace(" ", ",").split(",")
    nums = []
    for parte in partes:
        parte = parte.strip()
        if not parte:
            continue
        try:
            nums.append(int(float(parte)))
        except ValueError:
            continue
    return list(dict.fromkeys(nums))


def generar_hexagonos(nd=10, radio=1, semilla=1, c0=2, f0=3,
                      s_min=4, s_max=10, columnas="4,7", s_control=0.5):
    nd = int(nd)
    if nd < 1:
        raise ValueError("ND tiene que ser al menos 1")
    if nd > ND_MAX:
        raise ValueError("ND máximo en esta app: %s" % ND_MAX)
    s_min = float(s_min)
    s_max = float(s_max)
    if s_min > s_max:
        raise ValueError("La densidad mínima no puede ser mayor que la máxima")
    radio = float(radio)
    c0 = int(c0)
    f0 = int(f0)
    s_control = float(s_control)
    control = set(columnas_control(columnas))
    azar = random.Random(int(semilla))

    # c cambia más despacio que f, igual que rep(..., each) y rep(..., times).
    dh = []
    idh = 0
    for c in range(1, nd + 1):
        for f in range(1, nd + 1):
            idh += 1
            q = c - c0
            r = (f - f0) - q
            s = round(azar.uniform(s_min, s_max), 4)
            if c in control:
                s = s_control
            e = 0.1 if q == 0 and r == 0 else 0.0
            dh.append({
                "idh": idh,
                "c": c,
                "f": f,
                "q": q,
                "r": r,
                "x": radio * 1.5 * q,
                "y": radio * math.sqrt(3) * (q / 2.0 + r),
                "dia": 0,
                "S": round(s - e, 6),
                "E": e,
                "I": 0.0,
                "R": 0.0,
                "C": 0.0,
            })
    return dh


def conexiones_de(dh):
    lugar = {(h["q"], h["r"]): h["idh"] for h in dh}
    dv = []
    for pos, dq, dr in VECINOS:
        for h in dh:
            idhv = lugar.get((h["q"] + dq, h["r"] + dr))
            if idhv is None:
                continue
            dv.append({"idh": h["idh"], "pos": pos, "idhv": idhv})
    return dv


def actualizar_densidades(dh, p):
    p = completar_parametros(p)
    denom = p["ta_rec"] + p["ta_mor"]
    if denom == 0:
        raise ValueError("ta_rec y ta_mor no pueden sumar cero")
    salida = []
    for h in dh:
        lam = p["con_vi"] * h["I"] + p["con_ca"] * h["C"]
        d_se = (1 - math.exp(-lam)) * h["S"]
        d_ei = (1 - math.exp(-p["ta_inc"])) * h["E"]
        d_irc = (1 - math.exp(-denom)) * h["I"]
        d_ic = (p["ta_mor"] / denom) * d_irc
        d_ir = (p["ta_rec"] / denom) * d_irc
        d_cd = (1 - math.exp(-p["ta_des"])) * h["C"]
        salida.append({
            **h,
            "dia": int(h["dia"]) + 1,
            "S": h["S"] - d_se,
            "E": h["E"] + d_se - d_ei,
            "I": h["I"] + d_ei - d_irc,
            "R": h["R"] + d_ir,
            "C": h["C"] + d_ic - d_cd,
        })
    return salida


def contagio_hexagonos(dv, dh, p, azar):
    p = completar_parametros(p)
    por_idh = {}
    for enlace in dv:
        por_idh.setdefault(enlace["idh"], []).append(enlace)
    estado = {h["idh"]: h for h in dh}
    for h in dh:
        h["fcont"] = p["kappa"] * (p["con_vi"] * h["I"] + p["con_ca"] * h["C"])

    dc = []
    fuentes = [h for h in dh if h["fcont"] > 0]
    for h in fuentes:
        for enlace in por_idh.get(h["idh"], []):
            vecino = estado.get(enlace["idhv"])
            if vecino is None:
                continue
            prob = 1 - math.exp(-h["fcont"] * vecino["S"])
            prob = min(1.0, max(0.0, prob))
            # Un ensayo por arista, también si no hay contagio:
            # así la semilla recorre la misma secuencia de vecinos.
            cont = 1 if azar.random() < prob else 0
            if cont == 1:
                dc.append({
                    "dia": h["dia"],
                    "idh": h["idh"],
                    "idhv": enlace["idhv"],
                    "prob": prob,
                    "cont": cont,
                })

    recibidos = {}
    for fila in dc:
        recibidos[fila["idhv"]] = recibidos.get(fila["idhv"], 0) + fila["cont"]
    for h in dh:
        cont = recibidos.get(h["idh"], 0)
        pasa = min(h["S"], cont * 0.05 * h["S"])
        h["E"] = h["E"] + pasa
        h["S"] = h["S"] - pasa
        h.pop("fcont", None)
    return dc, dh


def simular_epidemia(dh, dv, dias=365, p=None, semilla=1):
    dias = int(dias)
    if dias < 1:
        raise ValueError("El número de días tiene que ser al menos 1")
    if dias > 1500:
        raise ValueError("El máximo de esta app es 1500 días")
    dh = [normalizar_hex(h) for h in dh]
    dv = [normalizar_enlace(e) for e in dv]
    azar = random.Random(int(semilla))
    piezas = []
    contagios = []
    for _ in range(dias):
        # El histórico guarda la mañana, antes del paso de ese día.
        piezas.extend({k: fila[k] for k in COLUMNAS_HEX} for fila in dh)
        dh = actualizar_densidades(dh, p)
        paso, dh = contagio_hexagonos(dv, dh, p, azar)
        contagios.extend(paso)
    return piezas, contagios


def normalizar_hex(h):
    def num(clave, defecto=0.0):
        valor = h.get(clave, defecto)
        if valor is None or valor == "":
            return defecto
        return float(valor)

    return {
        "idh": int(num("idh")),
        "c": int(num("c")),
        "f": int(num("f")),
        "q": int(num("q")),
        "r": int(num("r")),
        "x": num("x"),
        "y": num("y"),
        "dia": int(num("dia")),
        "S": num("S"),
        "E": num("E"),
        "I": num("I"),
        "R": num("R"),
        "C": num("C"),
    }


def normalizar_enlace(e):
    return {
        "idh": int(float(e.get("idh"))),
        "pos": "" if e.get("pos") is None else str(e.get("pos")),
        "idhv": int(float(e.get("idhv"))),
    }


def como_filas(tabla):
    if not tabla:
        return []
    if isinstance(tabla, list):
        return [dict(fila) for fila in tabla if isinstance(fila, dict)]
    if isinstance(tabla, dict):
        claves = [k for k in tabla.keys() if isinstance(tabla[k], list)]
        if not claves:
            return []
        n = len(tabla[claves[0]])
        return [{k: tabla[k][i] for k in claves} for i in range(n)]
    raise ValueError("La tabla no tiene un formato reconocible")


def columnas(filas, claves):
    filas = list(filas)
    if not filas:
        return {k: [] for k in claves}
    return {k: [fila.get(k) for fila in filas] for k in claves}


def cargar_mapa_json(ruta):
    if not os.path.isfile(ruta):
        return {
            "origen": "vacio",
            "aviso": "No está el archivo de hexágonos. Usa Generar mapa para crear el territorio.",
            "hexagonos": [],
            "conexiones": [],
        }
    with open(ruta, "r", encoding="utf-8") as fh:
        datos = json.load(fh)
    crudos = datos.get("hexagonos") if isinstance(datos, dict) else None
    dh = como_filas(crudos)
    if not dh:
        return {
            "origen": "vacio",
            "aviso": "agentes.json no trae hexágonos. Usa Generar mapa para crear el territorio.",
            "hexagonos": [],
            "conexiones": [],
        }
    dh = [normalizar_hex(h) for h in dh]
    dv = como_filas(datos.get("conexiones"))
    if dv:
        dv = [normalizar_enlace(e) for e in dv]
    else:
        dv = conexiones_de(dh)
    return {"origen": "agentes.json", "aviso": "", "hexagonos": dh, "conexiones": dv}


def pagina_acceso():
    return """<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Acceso · hexágonos</title><style>
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
background:#070907;color:#d7e3c6;font-family:Segoe UI,sans-serif}
form{width:min(420px,92vw);padding:1.4rem 1.3rem;border:1px solid #3d5a32;background:#10160f}
p.kicker{letter-spacing:.28em;color:#c5a572;font-size:.78rem;font-family:ui-monospace,monospace}
h1{margin:.2rem 0 1rem;letter-spacing:.12em;font-size:1.35rem;text-transform:uppercase}
label{display:block;color:#8aa078;margin-bottom:.35rem}
input{width:100%;padding:.55rem .6rem;background:#070907;color:#d7e3c6;border:1px solid #3d5a32}
button{margin-top:.9rem;padding:.6rem 1rem;letter-spacing:.14em;cursor:pointer;
background:#151c12;color:#7cff6b;border:1px solid #c5a572}
.aviso{color:#ff4d2e}
</style></head><body><form id="acceso">
<p class="kicker">SWINE DEFENSE</p><h1>Acceso</h1>
<label for="clave">Contraseña</label>
<input id="clave" name="clave" type="password" autocomplete="current-password" required>
<button type="submit">ENTRAR</button></form>
<script>
document.getElementById('acceso').addEventListener('submit', async function (ev) {
  ev.preventDefault();
  const r = await fetch('/entrar', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({clave: document.getElementById('clave').value})});
  if (r.ok) location.replace('/');
  else if (!document.querySelector('.aviso'))
    document.querySelector('h1').insertAdjacentHTML('afterend',
      '<p class="aviso">Contraseña incorrecta.</p>');
});
</script></body></html>"""


def token_cookie(cabecera):
    if not cabecera:
        return ""
    for parte in cabecera.split(";"):
        parte = parte.strip()
        if parte.startswith("hexa_sesion="):
            return unquote(parte.split("=", 1)[1])
    return ""


def clave_correcta(clave):
    if not isinstance(clave, str) or len(clave) != len(CLAVE) or not CLAVE:
        return False
    return hmac.compare_digest(clave.encode("utf-8"), CLAVE.encode("utf-8"))


def sesion_valida(handler):
    tok = token_cookie(handler.headers.get("Cookie"))
    return bool(tok) and tok in SESIONES


class App(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, formato, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), formato % args))

    def enviar(self, codigo, cuerpo, tipo, extra=None):
        if isinstance(cuerpo, str):
            datos = cuerpo.encode("utf-8")
        else:
            datos = cuerpo
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(datos)))
        self.send_header("Cache-Control", "no-store")
        if extra:
            for k, v in extra:
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(datos)

    def json(self, codigo, obj, extra=None):
        self.enviar(codigo, json.dumps(obj, ensure_ascii=False),
                    "application/json; charset=utf-8", extra)

    def libre(self, ruta):
        return ruta in ("/entrar", "/salud") or not CLAVE or sesion_valida(self)

    def do_GET(self):
        self.atender("GET")

    def do_POST(self):
        self.atender("POST")

    def do_OPTIONS(self):
        self.enviar(200, "", "text/plain", [
            ("Access-Control-Allow-Origin", "*"),
            ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type"),
        ])

    def leer_json(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        if n > 2_000_000:
            raise ValueError("El envío supera el tamaño admitido")
        bruto = self.rfile.read(n) if n else b""
        if not bruto:
            return {}
        return json.loads(bruto.decode("utf-8"))

    def atender(self, metodo):
        ruta = urlparse(self.path).path
        if not self.libre(ruta):
            if metodo == "GET" and ruta == "/":
                self.enviar(302, "", "text/plain", [("Location", "/entrar")])
                return
            self.json(401, {"error": "Hace falta la contraseña."})
            return
        try:
            if metodo == "GET":
                self.ruta_get(ruta)
            else:
                self.ruta_post(ruta)
        except Exception as exc:
            self.json(400, {"error": str(exc)})

    def ruta_get(self, ruta):
        if ruta == "/salud":
            self.json(200, {"ok": True, "servicio": "hexagonos", "motor": "Python"})
            return
        if ruta == "/entrar":
            self.enviar(200, pagina_acceso(), "text/html; charset=utf-8")
            return
        if ruta == "/":
            self.archivo(os.path.join(DIR, "index.html"), "text/html; charset=utf-8")
            return
        if ruta == "/parametros":
            params = {}
            params.update(parametros_defecto())
            params.update(parametros_mapa())
            self.json(200, {"params": params})
            return
        if ruta == "/generar":
            q = parse_qs(urlparse(self.path).query)
            def uno(nombre, defecto):
                return q.get(nombre, [defecto])[0]
            mapa = generar_hexagonos(
                nd=uno("nd", 10), radio=uno("radio", 1), semilla=uno("semilla", 1),
                c0=uno("c0", 2), f0=uno("f0", 3), s_min=uno("smin", 4),
                s_max=uno("smax", 10), columnas=uno("ccont", "4,7"),
                s_control=uno("scon", 0.5),
            )
            self.json(200, {
                "origen": "generado",
                "aviso": "",
                "hexagonos": columnas(mapa, COLUMNAS_HEX),
                "conexiones": columnas(conexiones_de(mapa), ("idh", "pos", "idhv")),
            })
            return
        if ruta == "/mapa":
            mapa = cargar_mapa_json(RUTA_AGENTES)
            self.json(200, {
                "origen": mapa["origen"],
                "aviso": mapa["aviso"],
                "hexagonos": columnas(mapa["hexagonos"], COLUMNAS_HEX if mapa["hexagonos"] else ()),
                "conexiones": columnas(mapa["conexiones"], ("idh", "pos", "idhv") if mapa["conexiones"] else ()),
            })
            return
        if ruta.startswith("/css/"):
            self.archivo(os.path.join(DIR, "css", os.path.basename(ruta)), "text/css; charset=utf-8")
            return
        if ruta.startswith("/js/"):
            self.archivo(os.path.join(DIR, "js", os.path.basename(ruta)), "text/javascript; charset=utf-8")
            return
        self.json(404, {"error": "No existe"})

    def ruta_post(self, ruta):
        if ruta == "/entrar":
            cuerpo = self.leer_json()
            clave = cuerpo.get("clave", "")
            if not isinstance(clave, str):
                clave = str(clave)
            if not clave_correcta(clave):
                self.json(401, {"ok": False})
                return
            tok = secrets.token_hex(16)
            SESIONES.add(tok)
            self.json(200, {"ok": True}, [(
                "Set-Cookie",
                "hexa_sesion=%s; HttpOnly; SameSite=Lax; Path=/; Max-Age=604800" % tok,
            )])
            return
        if ruta == "/simular":
            cuerpo = self.leer_json()
            dh = como_filas(cuerpo.get("hexagonos"))
            dv = como_filas(cuerpo.get("conexiones"))
            if not dh:
                raise ValueError("No hay hexágonos. Carga el mapa antes de simular.")
            if len(dh) > ND_MAX * ND_MAX:
                raise ValueError("Demasiados hexágonos para esta app")
            dias = int(cuerpo.get("dias") or 365)
            semilla = int(cuerpo.get("semilla") or 1)
            dhd, dc = simular_epidemia(dh, dv, dias=dias, p=cuerpo.get("params"), semilla=semilla)
            ultimo = max(fila["dia"] for fila in dhd) if dhd else 0
            self.json(200, {
                "dias": int(ultimo),
                "dhd": columnas(dhd, COLUMNAS_HEX),
                "dc": columnas(dc, COLUMNAS_DC),
            })
            return
        if ruta == "/guardar":
            cuerpo = self.leer_json()
            os.makedirs(RUTA_SALIDAS, exist_ok=True)
            f1 = os.path.join(RUTA_SALIDAS, "parametros.json")
            f2 = os.path.join(RUTA_SALIDAS, "conexiones.json")
            with open(f1, "w", encoding="utf-8") as fh:
                json.dump(cuerpo.get("params"), fh, ensure_ascii=False, indent=2)
            with open(f2, "w", encoding="utf-8") as fh:
                json.dump(cuerpo.get("conexiones"), fh, ensure_ascii=False, indent=2)
            self.json(200, {"ok": True, "parametros": f1, "conexiones": f2})
            return
        self.json(404, {"error": "No existe"})

    def archivo(self, ruta, tipo):
        if not os.path.isfile(ruta):
            self.json(404, {"error": "No está el archivo"})
            return
        with open(ruta, "rb") as fh:
            self.enviar(200, fh.read(), tipo)


def main():
    puerto = int(os.environ.get("PORT", "8765"))
    servidor = ThreadingHTTPServer(("0.0.0.0", puerto), App)
    print("Hexágonos en http://127.0.0.1:%s/" % puerto, flush=True)
    servidor.serve_forever()


if __name__ == "__main__":
    main()
