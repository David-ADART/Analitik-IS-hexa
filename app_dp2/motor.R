# motor.R
# Motor de la app de contención. Sigue simulacion_hexagonos_DP2.qmd:
#   1. se guarda el estado de la mañana
#   2. el SEIRC evoluciona dentro del hexágono y, si hay control,
#      bajan las densidades vivas o las carcasas
#   3. puede haber contagio hacia los vecinos
#   4. se detecta la infección y se abre el anillo cinegético
# Cargar este archivo no lanza ninguna simulación.
#
# En el cuaderno, la columna cortafuegos usa el nombre den_con,
# que no está definido. Aquí esa densidad es den_co.

library(dplyr)


# Valores que la pestaña MAPA enseña al abrir.
# pol_ccr y pol_prc salen de instrucciones_hexagonos_DP2.md.
# El cuaderno los deja en 2 y 0 cuando se ejecuta tal cual.
parametros_defecto <- function() {
  list(
    den_mi = 4,
    den_ma = 10,
    den_co = 0.5,
    ta_inc = 0.25,
    ta_mor = 0.16,
    ta_rec = 0.008,
    ta_des = 0.033,
    con_vi = 0.15,
    con_ca = 0.10,
    kappa = 0.05,
    pxi = 0.05,
    pxc = 0.1,
    pol_ccr = 3,
    pol_prc = 1,
    rdz = 0.05,
    rdc = 0.05,
    ND = 10,
    RH = 1,
    h00 = "2,3",
    CCONT = "999"
  )
}


# Solo rellena tasas numéricas. h00 y CCONT se leen aparte:
# as.numeric("2,3") daría NA y perdería el origen del mapa.
completar_parametros <- function(p = NULL) {
  base <- parametros_defecto()
  if (is.null(p)) return(base)
  for (nombre in names(base)) {
    if (nombre %in% c("h00", "CCONT")) next
    if (!is.null(p[[nombre]]) && !is.na(p[[nombre]])) {
      base[[nombre]] <- as.numeric(p[[nombre]])
    }
  }
  if (!is.null(p$h00) && nzchar(paste(p$h00, collapse = ""))) {
    base$h00 <- paste(p$h00, collapse = ",")
  }
  if (!is.null(p$CCONT)) base$CCONT <- paste(p$CCONT, collapse = ",")
  base
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


# "2,3" -> columna 2 y fila 3. Ese hexágono será el origen axial [0, 0].
origen_axial <- function(texto, c0 = 2, f0 = 3) {
  nums <- columnas_control(texto)
  if (length(nums) >= 2) return(as.integer(nums[1:2]))
  c(as.integer(c0), as.integer(f0))
}


# Mapa ND x ND. Vértice hacia la derecha, como geom_regon(angle = 0).
#   q = c - c0
#   r = (f - f0) - q
#   x = radio * 3/2 * q
#   y = radio * sqrt(3) * (q/2 + r)
generar_hexagonos <- function(nd = 10, radio = 1, semilla = 1, c0 = 2, f0 = 3,
                              den_mi = 4, den_ma = 10, columnas = 999,
                              den_co = 0.5) {
  nd <- as.integer(nd)
  if (nd < 1) stop("ND tiene que ser al menos 1")
  if (nd > 40) stop("ND máximo en esta app: 40")
  if (den_mi > den_ma) stop("La densidad mínima no puede ser mayor que la máxima")
  set.seed(as.integer(semilla))
  columnas <- columnas_control(columnas)

  # c cambia más despacio que f: rep(1:ND, each = ND) y rep(1:ND, ND).
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
  dh$S <- runif(nrow(dh), den_mi, den_ma)
  dh$E <- 0
  dh$I <- 0
  dh$R <- 0
  dh$C <- 0
  # inf: infección ya declarada. ccr: control cinegético. prc: retirada de carcasas.
  dh$inf <- 0
  dh$ccr <- 0
  dh$prc <- 0
  dh$S <- ifelse(dh$c %in% columnas, den_co, dh$S)
  # La epidemia entra por el origen axial, con 0.1 expuestos.
  dh$E <- ifelse(dh$q == 0 & dh$r == 0, 0.1, dh$E)
  dh$S <- dh$S - dh$E
  dh
}


# Seis vecinos, en el mismo orden que el cuaderno.
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


# Un día dentro de cada hexágono.
# Los flujos se calculan con el estado de la mañana.
# Después, si el hexágono está en control cinegético (ccr = 1),
# S, E, I y R se multiplican por (1 - rdz).
# Si hay retirada de carcasas (prc = 1), C se multiplica por (1 - rdc).
actualizar_densidades <- function(DH, p) {
  p <- completar_parametros(p)
  denom <- p$ta_rec + p$ta_mor
  if (denom == 0) stop("ta_rec y ta_mor no pueden sumar cero")

  lambda <- p$con_vi * DH$I + p$con_ca * DH$C
  d_SE <- (1 - exp(-lambda)) * DH$S
  d_EI <- (1 - exp(-p$ta_inc)) * DH$E
  d_IRC <- (1 - exp(-denom)) * DH$I
  d_IC <- (p$ta_mor / denom) * d_IRC
  d_IR <- (p$ta_rec / denom) * d_IRC
  d_CD <- (1 - exp(-p$ta_des)) * DH$C

  vivos <- 1 - p$rdz * DH$ccr
  carcasas <- 1 - p$rdc * DH$prc
  DH$dia <- DH$dia + 1L
  DH$S <- (DH$S - d_SE) * vivos
  DH$E <- (DH$E + d_SE - d_EI) * vivos
  DH$I <- (DH$I + d_EI - d_IRC) * vivos
  DH$R <- (DH$R + d_IR) * vivos
  DH$C <- (DH$C + d_IC - d_CD) * carcasas
  DH
}


# Contagio hacia cada vecino.
# fcont = kappa * (con_vi * I + con_ca * C)
# P = 1 - exp(-fcont * S del vecino)
# Cada contagio que sale pasa un 5 % de los susceptibles del vecino a expuestos.
contagio_hexagonos <- function(DV, DH, p) {
  p <- completar_parametros(p)
  vacio <- data.frame(
    dia = numeric(), idh = numeric(), idhv = numeric(),
    prob = numeric(), cont = numeric()
  )
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
  DH$E <- DH$E + DH$cont * 0.05 * DH$S
  DH$S <- DH$S - DH$cont * 0.05 * DH$S
  DH$cont <- NULL
  list(DC = DC, DH = DH)
}


# Detección y activación del perímetro.
# La probabilidad diaria es pxi*I + pxc*C, entre 0 y 1.
# Si el hexágono ya estaba declarado (inf = 1), la probabilidad se queda en 1:
# la declaración no se olvida.
# pol_ccr es la profundidad del anillo. Cada vuelta del bucle marca
# a los vecinos de los hexágonos que ya están en control cinegético.
# La retirada de carcasas (prc) solo se declara en el hexágono detectado,
# no en todo el anillo.
deteccion_hexagono <- function(DH, DV, p) {
  p <- completar_parametros(p)
  fuerza <- pmin(1, pmax(0, p$pxi * DH$I + p$pxc * DH$C))
  prob <- pmax(fuerza, DH$inf)
  prob <- pmin(1, pmax(0, prob))
  DH$inf <- rbinom(nrow(DH), 1, prob)
  DH$ccr <- DH$inf * sign(p$pol_ccr)
  DH$prc <- DH$inf * p$pol_prc

  profundidad <- as.integer(p$pol_ccr)
  if (!is.na(profundidad) && profundidad >= 1 && nrow(DV) > 0) {
    for (i in seq_len(profundidad)) {
      origenes <- DH$idh[DH$ccr == 1]
      if (length(origenes) == 0) break
      vecinos <- unique(DV$idhv[DV$idh %in% origenes])
      DH$ccr[DH$idh %in% vecinos] <- 1
    }
  }
  DH
}


# Recorre `dias` jornadas. El histórico guarda la mañana, antes del paso.
# Con 365 días el primer registro es el día 0 y el último es el 364.
simular_epidemia <- function(dh, dv, dias = 365, p = NULL, semilla = 1) {
  dias <- as.integer(dias)
  if (dias < 1) stop("El número de días tiene que ser al menos 1")
  if (dias > 1500) stop("El máximo de esta app es 1500 días")
  set.seed(as.integer(semilla))

  dh <- as.data.frame(dh)
  dv <- as.data.frame(dv)
  for (col in c("S", "E", "I", "R", "C", "inf", "ccr", "prc", "dia")) {
    if (is.null(dh[[col]])) dh[[col]] <- 0
    dh[[col]] <- as.numeric(dh[[col]])
  }
  dh$dia <- as.integer(dh$dia)
  if (nrow(dv) == 0) {
    dv <- data.frame(idh = numeric(), pos = character(), idhv = numeric())
  }
  dv$idh <- as.numeric(dv$idh)
  dv$idhv <- as.numeric(dv$idhv)

  piezas <- vector("list", dias)
  contagios <- list()
  n_cont <- 0L
  columnas_hist <- c("idh", "x", "y", "c", "f", "dia", "S", "E", "I", "R", "C", "inf", "ccr", "prc")

  for (d in seq_len(dias)) {
    piezas[[d]] <- dh[, columnas_hist]
    dh <- actualizar_densidades(dh, p)
    paso <- contagio_hexagonos(dv, dh, p)
    dh <- paso$DH
    if (nrow(paso$DC) > 0) {
      n_cont <- n_cont + 1L
      contagios[[n_cont]] <- paso$DC
    }
    dh <- deteccion_hexagono(dh, dv, p)
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


# Lee datos/agentes.json solo si trae la tabla "hexagonos".
# Si no la trae, no se inventa un mapa: hay que pulsar Generar mapa.
cargar_mapa_json <- function(ruta) {
  vacio <- data.frame()
  if (!file.exists(ruta)) {
    return(list(
      origen = "vacio",
      aviso = "No está el archivo de hexágonos. Usa Generar mapa para crear el territorio.",
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
  for (col in c("inf", "ccr", "prc")) {
    if (is.null(dh[[col]])) dh[[col]] <- 0
  }
  if (!is.null(datos$conexiones) && nrow(as.data.frame(datos$conexiones)) > 0) {
    dv <- as.data.frame(datos$conexiones)
  } else {
    dv <- conexiones_de(dh)
  }
  list(origen = "agentes.json", aviso = "", hexagonos = dh, conexiones = dv)
}
