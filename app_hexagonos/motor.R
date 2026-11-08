# motor.R
# Motor de la epidemia en hexágonos para la app HTML.
# Sigue el modelo de simulacion_hexagonos_DP.qmd:
#   cada día, primero evoluciona el SEIRC dentro de cada hexágono
#   y después puede haber contagio hacia los hexágonos vecinos.
# Cargar este archivo no lanza ninguna simulación.

library(dplyr)


# Valores iniciales de la pestaña MAPA.
# Los seis primeros entran en el paso diario. Los de bioseguridad
# (pamp_d ... pvap_d) se guardan con el mapa; el bucle diario del
# cuaderno todavía no los usa porque la capa de granjas está solo esbozada.
parametros_defecto <- function() {
  list(
    ta_inc = 0.25,
    ta_mor = 0.16,
    ta_rec = 0.008,
    ta_des = 0.033,
    con_vi = 0.15,
    con_ca = 0.10,
    kappa  = 0.05,
    pamp_d = 0.1,
    pamc_d = 0.05,
    pavp_d = 0.8,
    pavc_d = 0.1,
    pmap_d = 0.1,
    pvap_d = 0.8
  )
}


# Parámetros con los que se construye el mapa, aparte de las tasas.
# CCONT son las columnas (separadas por comas) donde S no es aleatoria.
parametros_mapa <- function() {
  list(
    ND = 10,
    RH = 1,
    CCONT = "4,7",
    Smin = 4,
    Smax = 10,
    Scon = 0.5
  )
}


# "4, 7" o un vector numérico -> columnas enteras, sin repetir.
columnas_control <- function(texto) {
  if (is.null(texto) || length(texto) == 0) return(integer())
  if (is.numeric(texto) && length(texto) > 1) return(unique(as.integer(texto)))
  partes <- unlist(strsplit(paste(texto, collapse = ","), "[,;[:space:]]+"))
  partes <- partes[nzchar(partes)]
  nums <- suppressWarnings(as.integer(partes))
  unique(nums[!is.na(nums)])
}


# Completa la lista que llega de la app con los valores por defecto.
# Así un campo vacío no deja la tasa en NULL.
completar_parametros <- function(p = NULL) {
  base <- parametros_defecto()
  if (is.null(p)) return(base)
  for (nombre in names(base)) {
    if (!is.null(p[[nombre]]) && !is.na(p[[nombre]])) {
      base[[nombre]] <- as.numeric(p[[nombre]])
    }
  }
  base
}


# Mapa ND x ND. El hexágono [c0, f0] pasa a ser el origen axial [q=0, r=0].
# Orientación del cuaderno: vértice hacia la derecha (lado plano arriba).
#   q = c - c0
#   r = (f - f0) - q
#   x = radio * 3/2 * q
#   y = radio * sqrt(3) * (q/2 + r)
generar_hexagonos <- function(nd = 10, radio = 1, semilla = 1, c0 = 2, f0 = 3,
                              s_min = 4, s_max = 10, columnas = c(4, 7),
                              s_control = 0.5) {
  nd <- as.integer(nd)
  if (nd < 1) stop("ND tiene que ser al menos 1")
  if (s_min > s_max) stop("La densidad mínima no puede ser mayor que la máxima")
  set.seed(as.integer(semilla))
  columnas <- columnas_control(columnas)

  dh <- data.frame(
    idh = seq_len(nd * nd),
    c = rep(seq_len(nd), each = nd),
    f = rep(seq_len(nd), times = nd)
  )
  dh$q <- dh$c - as.integer(c0)
  dh$r <- (dh$f - as.integer(f0)) - dh$q
  dh$x <- radio * (3 / 2) * dh$q
  dh$y <- radio * sqrt(3) * (dh$q / 2 + dh$r)
  dh$dia <- 0L
  # Densidad aleatoria entre Smin y Smax, salvo en las columnas de control.
  dh$S <- round(runif(nrow(dh), s_min, s_max), 4)
  dh$E <- 0
  dh$I <- 0
  dh$R <- 0
  dh$C <- 0
  dh$S <- ifelse(dh$c %in% columnas, s_control, dh$S)
  # La epidemia empieza en el origen axial [0,0], con 0.1 expuestos.
  dh$E <- ifelse(dh$q == 0 & dh$r == 0, 0.1, dh$E)
  dh$S <- round(dh$S - dh$E, 6)
  dh
}


# Seis vecinos axiales, en el mismo orden que el cuaderno.
# Un borde del mapa simplemente no tiene ese vecino.
conexiones_de <- function(dh) {
  desplazamientos <- data.frame(
    pos = c("NO", "N", "NE", "SE", "S", "SO"),
    dq = c(-1, 0, 1, 1, 0, -1),
    dr = c(1, 1, 0, -1, -1, 0),
    stringsAsFactors = FALSE
  )
  piezas <- lapply(seq_len(nrow(desplazamientos)), function(i) {
    data.frame(
      idh = dh$idh,
      pos = desplazamientos$pos[i],
      qv = dh$q + desplazamientos$dq[i],
      rv = dh$r + desplazamientos$dr[i],
      stringsAsFactors = FALSE
    )
  })
  dv <- bind_rows(piezas)
  claves <- data.frame(qv = dh$q, rv = dh$r, idhv = dh$idh)
  dv <- left_join(dv, claves, by = c("qv", "rv"))
  dv <- dv[!is.na(dv$idhv), c("idh", "pos", "idhv")]
  rownames(dv) <- NULL
  dv
}


# Un día dentro de cada hexágono. Las tasas no se reescalan por la
# densidad: el cuaderno usa con_vi y con_ca tal como están.
# Flujos, todos calculados con el estado de la mañana:
#   S -> E por vivos y carcasas
#   E -> I por incubación
#   I -> R o C por recuperación y mortalidad
#   C disminuye por descomposición
actualizar_densidades <- function(DH, p) {
  p <- completar_parametros(p)
  lambda <- p$con_vi * DH$I + p$con_ca * DH$C
  d_SE <- (1 - exp(-lambda)) * DH$S
  d_EI <- (1 - exp(-p$ta_inc)) * DH$E
  d_IRC <- (1 - exp(-(p$ta_rec + p$ta_mor))) * DH$I
  d_IC <- (p$ta_mor / (p$ta_rec + p$ta_mor)) * d_IRC
  d_IR <- (p$ta_rec / (p$ta_rec + p$ta_mor)) * d_IRC
  d_CD <- (1 - exp(-p$ta_des)) * DH$C

  DH$dia <- DH$dia + 1L
  DH$S <- DH$S - d_SE
  DH$E <- DH$E + d_SE - d_EI
  DH$I <- DH$I + d_EI - d_IRC
  DH$R <- DH$R + d_IR
  DH$C <- DH$C + d_IC - d_CD
  DH
}


# Contagio de un hexágono con infección hacia cada vecino sano o no.
# fcont = kappa * (con_vi * I + con_ca * C)
# P = 1 - exp(-fcont * S_vecino)
# Cada contagio que ocurre pasa un 5 % de los susceptibles del vecino a expuestos.
contagio_hexagonos <- function(DV, DH, p) {
  p <- completar_parametros(p)
  vacio <- data.frame(dia = numeric(), idh = numeric(), idhv = numeric(),
                      prob = numeric(), cont = numeric())

  DH$fcont <- p$kappa * (p$con_vi * DH$I + p$con_ca * DH$C)
  fuentes <- DH[DH$fcont > 0, c("dia", "idh", "fcont")]
  if (nrow(fuentes) == 0 || nrow(DV) == 0) {
    DH$fcont <- NULL
    return(list(DC = vacio, DH = DH))
  }

  DC <- left_join(fuentes, DV, by = "idh")
  DC <- DC[!is.na(DC$idhv), ]
  suseptibles <- data.frame(idhv = DH$idh, S = DH$S)
  DC <- left_join(DC, suseptibles, by = "idhv")
  DC <- DC[!is.na(DC$S), ]
  if (nrow(DC) == 0) {
    DH$fcont <- NULL
    return(list(DC = vacio, DH = DH))
  }

  DC$prob <- 1 - exp(-DC$fcont * DC$S)
  DC$prob <- pmin(pmax(DC$prob, 0), 1)
  DC$cont <- rbinom(nrow(DC), 1, DC$prob)
  DC <- DC[DC$cont == 1, c("dia", "idh", "idhv", "prob", "cont")]
  rownames(DC) <- NULL

  DH$fcont <- NULL
  if (nrow(DC) == 0) return(list(DC = vacio, DH = DH))

  recibidos <- DC |>
    group_by(idh = idhv) |>
    summarise(cont = sum(cont), .groups = "drop")
  DH <- left_join(DH, recibidos, by = "idh")
  DH$cont <- ifelse(is.na(DH$cont), 0, DH$cont)
  # No se puede pasar a expuestos más susceptible del que hay.
  pasa <- pmin(DH$S, DH$cont * 0.05 * DH$S)
  DH$E <- DH$E + pasa
  DH$S <- DH$S - pasa
  DH$cont <- NULL
  list(DC = DC, DH = DH)
}


# Recorre `dias` jornadas. El histórico guarda el estado de la mañana,
# antes del paso de ese día, igual que el bucle del cuaderno.
# Con dias = 365 el primer día guardado es 0 y el último es 364.
simular_epidemia <- function(dh, dv, dias = 365, p = NULL, semilla = 1) {
  dias <- as.integer(dias)
  if (dias < 1) stop("El número de días tiene que ser al menos 1")
  if (dias > 1500) stop("El máximo de esta app es 1500 días")
  set.seed(as.integer(semilla))

  dh <- as.data.frame(dh)
  dv <- as.data.frame(dv)
  for (col in c("S", "E", "I", "R", "C", "dia")) {
    dh[[col]] <- as.numeric(dh[[col]])
  }
  dh$dia <- as.integer(dh$dia)
  dv$idh <- as.numeric(dv$idh)
  dv$idhv <- as.numeric(dv$idhv)

  piezas <- vector("list", dias)
  contagios <- list()
  n_cont <- 0L

  for (d in seq_len(dias)) {
    piezas[[d]] <- dh[, c("idh", "x", "y", "c", "f", "dia", "S", "E", "I", "R", "C")]
    dh <- actualizar_densidades(dh, p)
    paso <- contagio_hexagonos(dv, dh, p)
    dh <- paso$DH
    if (nrow(paso$DC) > 0) {
      n_cont <- n_cont + 1L
      contagios[[n_cont]] <- paso$DC
    }
  }

  dhd <- bind_rows(piezas)
  dc <- if (n_cont == 0) {
    data.frame(dia = numeric(), idh = numeric(), idhv = numeric(),
               prob = numeric(), cont = numeric())
  } else {
    bind_rows(contagios)
  }
  list(dhd = dhd, dc = dc)
}


# Lee datos/agentes.json. Solo usa el archivo si trae la tabla "hexagonos".
# El mapa aleatorio se pide aparte, con generar_hexagonos().
cargar_mapa_json <- function(ruta) {
  vacio <- data.frame()
  if (!file.exists(ruta)) {
    return(list(
      origen = "vacio",
      aviso = paste("No está", ruta),
      hexagonos = vacio,
      conexiones = vacio
    ))
  }

  datos <- jsonlite::fromJSON(ruta, simplifyVector = TRUE)
  if (is.null(datos$hexagonos) || nrow(as.data.frame(datos$hexagonos)) == 0) {
    return(list(
      origen = "vacio",
      aviso = "agentes.json no trae hexágonos. Usa Generar mapa para crear el territorio.",
      hexagonos = vacio,
      conexiones = vacio
    ))
  }

  dh <- as.data.frame(datos$hexagonos)
  if (is.null(dh$dia)) dh$dia <- 0L
  if (!is.null(datos$conexiones) && nrow(as.data.frame(datos$conexiones)) > 0) {
    dv <- as.data.frame(datos$conexiones)
  } else {
    dv <- conexiones_de(dh)
  }
  list(origen = "agentes.json", aviso = "", hexagonos = dh, conexiones = dv)
}
