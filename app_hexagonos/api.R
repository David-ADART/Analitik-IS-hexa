# api.R
# Sirve la app HTML y ejecuta el motor en R.
#
# Desde la carpeta del proyecto:
#   Rscript -e 'plumber::plumb("app_hexagonos/api.R")$run(host="127.0.0.1", port=8765)'
# Luego abre http://127.0.0.1:8765/

Sys.setlocale("LC_ALL", "en_US.UTF-8")

this_dir <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile)),
  error = function(e) getwd()
)
if (!file.exists(file.path(this_dir, "motor.R"))) {
  this_dir <- file.path(getwd(), "app_hexagonos")
}

# local = TRUE deja las funciones en el entorno de esta API.
# Sin eso, plumber no las ve desde los endpoints.
source(file.path(this_dir, "motor.R"), local = TRUE)
proyecto <- normalizePath(file.path(this_dir, ".."))
ruta_agentes <- file.path(proyecto, "datos", "agentes.json")
ruta_salidas <- file.path(this_dir, "salidas")

# HEXA_CLAVE vacía deja la app abierta (uso local).
# Con valor, hace falta esa contraseña para ver la app y llamar a la API.
clave_app <- Sys.getenv("HEXA_CLAVE", "")
sesiones <- new.env(parent = emptyenv())

token_cookie <- function(req) {
  h <- req$HTTP_COOKIE
  if (is.null(h) || !nzchar(h)) return("")
  m <- regexec("(?:^|;\\s*)hexa_sesion=([^;]+)", h)
  r <- regmatches(h, m)[[1]]
  if (length(r) < 2) return("")
  utils::URLdecode(r[2])
}

sesion_valida <- function(req) {
  tok <- token_cookie(req)
  nzchar(tok) && exists(tok, envir = sesiones, inherits = FALSE)
}

clave_correcta <- function(clave) {
  if (!is.character(clave) || length(clave) != 1 || is.na(clave)) return(FALSE)
  a <- charToRaw(enc2utf8(clave))
  b <- charToRaw(enc2utf8(clave_app))
  length(a) == length(b) && identical(a, b)
}

pagina_acceso <- function(error = FALSE) {
  aviso <- if (error) "<p class=\"aviso\">Contraseña incorrecta.</p>" else ""
  paste0(
    "<!DOCTYPE html><html lang=\"es\"><head><meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    "<title>Acceso · hexágonos</title><style>",
    "body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;",
    "background:#070907;color:#d7e3c6;font-family:Segoe UI,sans-serif}",
    "form{width:min(420px,92vw);padding:1.4rem 1.3rem;border:1px solid #3d5a32;background:#10160f}",
    "p.kicker{letter-spacing:.28em;color:#c5a572;font-size:.78rem;font-family:ui-monospace,monospace}",
    "h1{margin:.2rem 0 1rem;letter-spacing:.12em;font-size:1.35rem;text-transform:uppercase}",
    "label{display:block;color:#8aa078;margin-bottom:.35rem}",
    "input{width:100%;padding:.55rem .6rem;background:#070907;color:#d7e3c6;border:1px solid #3d5a32}",
    "button{margin-top:.9rem;padding:.6rem 1rem;letter-spacing:.14em;cursor:pointer;",
    "background:#151c12;color:#7cff6b;border:1px solid #c5a572}",
    ".aviso{color:#ff4d2e}",
    "</style></head><body><form id=\"acceso\">",
    "<p class=\"kicker\">SWINE DEFENSE</p><h1>Acceso</h1>",
    aviso,
    "<label for=\"clave\">Contraseña</label>",
    "<input id=\"clave\" name=\"clave\" type=\"password\" autocomplete=\"current-password\" required>",
    "<button type=\"submit\">ENTRAR</button></form>",
    "<script>",
    "document.getElementById('acceso').addEventListener('submit', async function (ev) {",
    "ev.preventDefault();",
    "const r = await fetch('/entrar', {method:'POST', headers:{'Content-Type':'application/json'},",
    "body: JSON.stringify({clave: document.getElementById('clave').value})});",
    "if (r.ok) location.replace('/');",
    "else { var a = document.querySelector('.aviso');",
    "if (!a) document.querySelector('h1').insertAdjacentHTML('afterend',",
    "'<p class=\"aviso\">Contraseña incorrecta.</p>'); }",
    "});</script></body></html>"
  )
}


leer_cuerpo <- function(req) {
  raw <- req$postBody
  if (is.null(raw) || !nzchar(raw)) return(list())
  jsonlite::fromJSON(raw, simplifyVector = TRUE)
}

como_tabla <- function(x) {
  if (is.null(x)) return(data.frame())
  as.data.frame(x, stringsAsFactors = FALSE)
}

# jsonlite en modo columnas: el navegador reconstruye las filas.
columnas <- function(df) {
  df <- como_tabla(df)
  if (nrow(df) == 0) {
    return(lapply(df, function(col) if (is.character(col)) character() else numeric()))
  }
  lapply(df, function(col) {
    if (is.factor(col)) as.character(col) else col
  })
}


#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type")
  if (identical(req$REQUEST_METHOD, "OPTIONS")) {
    res$status <- 200
    return(list(ok = TRUE))
  }
  plumber::forward()
}


#* @filter acceso
function(req, res) {
  if (!nzchar(clave_app)) return(plumber::forward())
  ruta <- req$PATH_INFO
  if (is.null(ruta) || !nzchar(ruta)) ruta <- "/"
  if (ruta %in% c("/entrar", "/salud")) return(plumber::forward())
  if (sesion_valida(req)) return(plumber::forward())
  if (identical(req$REQUEST_METHOD, "GET") && identical(ruta, "/")) {
    res$status <- 302
    res$setHeader("Location", "/entrar")
    return(list())
  }
  res$status <- 401
  list(error = "Hace falta la contraseña.")
}


#* @get /entrar
#* @serializer contentType list(type = "text/html; charset=utf-8")
function() {
  pagina_acceso()
}


#* @post /entrar
#* @serializer json list(auto_unbox = TRUE)
function(req, res) {
  body <- tryCatch(leer_cuerpo(req), error = function(e) list())
  clave <- if (is.null(body$clave)) "" else as.character(body$clave)
  if (!clave_correcta(clave)) {
    res$status <- 401
    return(list(ok = FALSE))
  }
  tok <- paste(sample(c(letters, LETTERS, 0:9), 32, replace = TRUE), collapse = "")
  sesiones[[tok]] <- TRUE
  res$setHeader(
    "Set-Cookie",
    paste0("hexa_sesion=", tok, "; HttpOnly; SameSite=Lax; Path=/; Max-Age=604800")
  )
  list(ok = TRUE)
}


#* @get /salud
#* @serializer json list(auto_unbox = TRUE)
function() {
  list(ok = TRUE, servicio = "hexagonos", motor = "R")
}


#* @get /parametros
#* @serializer json list(auto_unbox = TRUE)
function() {
  list(params = c(parametros_defecto(), parametros_mapa()))
}


#* Genera el mapa ND x ND con densidades aleatorias y columnas de control.
#* @get /generar
#* @serializer json list(auto_unbox = TRUE, na = "null")
function(nd = 10, radio = 1, semilla = 1, c0 = 2, f0 = 3,
         smin = 4, smax = 10, ccont = "4,7", scon = 0.5, res) {
  mapa <- tryCatch(
    generar_hexagonos(
      nd = as.numeric(nd),
      radio = as.numeric(radio),
      semilla = as.numeric(semilla),
      c0 = as.numeric(c0),
      f0 = as.numeric(f0),
      s_min = as.numeric(smin),
      s_max = as.numeric(smax),
      columnas = ccont,
      s_control = as.numeric(scon)
    ),
    error = function(e) e
  )
  if (inherits(mapa, "error")) {
    res$status <- 400
    return(list(error = mapa$message))
  }
  list(
    origen = "generado",
    aviso = "",
    hexagonos = columnas(mapa),
    conexiones = columnas(conexiones_de(mapa))
  )
}


#* @get /mapa
#* @serializer json list(auto_unbox = TRUE, na = "null")
function() {
  mapa <- cargar_mapa_json(ruta_agentes)
  list(
    origen = mapa$origen,
    aviso = mapa$aviso,
    hexagonos = columnas(mapa$hexagonos),
    conexiones = columnas(mapa$conexiones)
  )
}


#* @post /simular
#* @serializer json list(auto_unbox = TRUE, na = "null")
function(req, res) {
  body <- tryCatch(leer_cuerpo(req), error = function(e) {
    res$status <- 400
    return(list(error = paste("JSON no válido:", e$message)))
  })
  if (!is.null(body$error)) return(body)

  resultado <- tryCatch({
    dh <- como_tabla(body$hexagonos)
    dv <- como_tabla(body$conexiones)
    if (nrow(dh) == 0) stop("No hay hexágonos. Carga el mapa antes de simular.")
    if (nrow(dv) == 0) {
      dv <- data.frame(idh = numeric(), pos = character(), idhv = numeric())
    }
    dias <- if (is.null(body$dias)) 365 else as.integer(body$dias)
    semilla <- if (is.null(body$semilla)) 1 else as.integer(body$semilla)
    sim <- simular_epidemia(dh, dv, dias = dias, p = body$params, semilla = semilla)
    list(
      dias = as.integer(max(sim$dhd$dia)),
      dhd = columnas(sim$dhd),
      dc = columnas(sim$dc)
    )
  }, error = function(e) {
    res$status <- 400
    list(error = e$message)
  })
  resultado
}


#* Guarda parámetros y conexiones en app_hexagonos/salidas/
#* @post /guardar
#* @serializer json list(auto_unbox = TRUE, na = "null")
function(req, res) {
  body <- tryCatch(leer_cuerpo(req), error = function(e) {
    res$status <- 400
    return(list(error = e$message))
  })
  if (!is.null(body$error)) return(body)
  dir.create(ruta_salidas, showWarnings = FALSE, recursive = TRUE)
  f1 <- file.path(ruta_salidas, "parametros.json")
  f2 <- file.path(ruta_salidas, "conexiones.json")
  writeLines(jsonlite::toJSON(body$params, auto_unbox = TRUE, pretty = TRUE), f1)
  writeLines(jsonlite::toJSON(body$conexiones, auto_unbox = TRUE, pretty = TRUE, na = "null"), f2)
  list(ok = TRUE, parametros = f1, conexiones = f2)
}


#* @get /
function(res) {
  plumber::include_file(
    file.path(this_dir, "index.html"),
    res,
    content_type = "text/html; charset=utf-8"
  )
}


#* @get /css/<archivo>
function(archivo, res) {
  plumber::include_file(
    file.path(this_dir, "css", basename(archivo)),
    res,
    content_type = "text/css; charset=utf-8"
  )
}

#* @get /js/<archivo>
function(archivo, res) {
  plumber::include_file(
    file.path(this_dir, "js", basename(archivo)),
    res,
    content_type = "text/javascript; charset=utf-8"
  )
}
