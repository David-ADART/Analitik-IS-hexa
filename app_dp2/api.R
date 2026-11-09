# api.R
# Sirve la app de contención cinegética y ejecuta el motor en R.
#
# Desde la carpeta del proyecto:
#   Rscript -e 'plumber::plumb("app_dp2/api.R")$run(host="127.0.0.1", port=8770)'
# Luego abre http://127.0.0.1:8770/

Sys.setlocale("LC_ALL", "en_US.UTF-8")

this_dir <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile)),
  error = function(e) getwd()
)
if (!file.exists(file.path(this_dir, "motor.R"))) {
  this_dir <- file.path(getwd(), "app_dp2")
}

source(file.path(this_dir, "motor.R"), local = TRUE)
proyecto <- normalizePath(file.path(this_dir, ".."))
ruta_agentes <- file.path(proyecto, "datos", "agentes.json")
ruta_salidas <- file.path(this_dir, "salidas")


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


#* @get /salud
#* @serializer json list(auto_unbox = TRUE)
function() {
  list(ok = TRUE, servicio = "contencion", motor = "R")
}


#* @get /parametros
#* @serializer json list(auto_unbox = TRUE)
function() {
  list(params = parametros_defecto())
}


#* Genera el territorio. ccont no se llama "columnas": esa función ya existe.
#* @get /generar
#* @serializer json list(auto_unbox = TRUE, na = "null")
function(nd = 10, radio = 1, semilla = 1, c0 = 2, f0 = 3,
         denmi = 4, denma = 10, ccont = "999", denco = 0.5, res) {
  mapa <- tryCatch(
    generar_hexagonos(
      nd = as.numeric(nd),
      radio = as.numeric(radio),
      semilla = as.numeric(semilla),
      c0 = as.numeric(c0),
      f0 = as.numeric(f0),
      den_mi = as.numeric(denmi),
      den_ma = as.numeric(denma),
      columnas = ccont,
      den_co = as.numeric(denco)
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
    if (nrow(dh) == 0) stop("No hay hexágonos. Genera el mapa antes de simular.")
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


#* Guarda parámetros y conexiones en app_dp2/salidas/
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
