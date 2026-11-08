# App de demostración de epidemia animal

Quiero que tomes el archivo "simulacion_hexagonos_DP.qmd" y basado en el haz una aplicación en HTML para ejecutar simulaciones

## Especificación de la interface

- Quiero que el interface sea un cuadro de mandos con estilo táctico militar
- El interface tendrá cuatro pestañas llamadas: "MAPA", "SIMULACION", "RESULTADOS", "ANALISIS". Estas etiquetas tendrán un tamaño grande

### Dentro de la pestaña "HEXAGONOS"

- Incluye una sección de cuadros para incluir valores de los parámetros. Los valores por defecto son:
  - ta_inc = 0.25 Tasa de incubación (periodo medio = 4 días)
  - ta_mor = 0.16 Mortality rate por PPA (duración de la enfermedad \~6 días)
  - ta_rec = 0.008 Tasa de recuperación (supervivencia \~5%)
  - ta_des = 0.033  
  - con_vi = 0.15 Contagio por contacto directo con jabalíes vivos
  - con_ca = 0.10 Contagio ambiental por carcasas en el terreno
  - kappa = 0.05 Fracción de la fuerza de infección que cruza al hexágono vecino
  - pamp_d = 0.1 prob contagio agente en produccion a medio
  - pamc_d = 0.05 prob contagio agente clausurado a medio
  - pavp_d = 0.8 prob contagio agente en producción a vehículo
  - pavc_d = 0.1 prob contagio agente clausurado a vehículo
  - pmap_d = 0.1 prob contagio de medio a agente en producción
  - pvap_d = 0.8 prob contagio de vehículo a agente en produc.
  - ND: El número de hexagonos en diagonal principal
  - RH: El radio de los hexágonos
  - Un cuadro donde se se puedan modificar las columnas de control donde se van a poner densidad de susceptibles inicial muy baja para todas las celdas en esa columna. Las columnas se separaran con comas.
  - Cuadro con densidad minima aleatoria
  - Cuadro con densidad maxima aleatoria
  - Un cuadro con la densidad inicial que se pondrá en las columnas control
- Pero que el usuario también pueda modificar estos parámetros si lo desea. Para cada parámetro debe aparecer un nombre en palabras corto, y el símbolo entre paréntesis. Junto a este, pon un símbolo "?", dónde al pasar el ratón abra una pequeña leyenda explicando el significado del parámetro. Los parámetros aparecerán en modo lista en tres columnas
- Hay un botón de "guardar parámetros" para guardar estos y las conexiones que se hayan hecho en dos archivos
- Pon un boton de "Generar mapa" que generará el mapa con densidades aleatorias, excepto en las columnas control, tal y como especifica el código R.
- Pon un botón de "Cargar mapa". Esto debe leer los hexágonos de un archivo "agentes.json", tras lo cual se generaran las tablas hexágonos.
- debajo aparece la **tabla de hexágonos** con las columnas de todas sus variables, todas las variables pueden ser modificadas por el usuario en esta tabla. Las variables S,E,I,R,C serán actualizadas por las simulaciones cada día de simulación.
- Todas las tablas deben tener un botón que permita descargarlas en CSV

### Dentro de la pestaña "SIMULACION"

- Hay un mapa de los hexágonos dibujado con la función "dibujar_hexagonos". Estos puedes estar coloreados según las densidades S, E, I, R o C o alguna fórmula a partir de estas. Junto al mapa quiero que aparezca:
  - Un cuadro de texto donde se pueda poner la fórmula con las densidades
  - Un cuadro de texto dónde pueda poner una explicación de la fórmula.
  - Un boton para actualizar el mapa cuando cambio la formula.
  - Un cuadro numérico que muestra el día de la simulacion que representa el mapa. Si cambio el numero de día en ese cuadro, el mapa se actualizará a ese día. Por defecto el día representado será el 0.
- Habrá un botón de play/pause simulación para ponerla en marcha, pausarla y reactivarla
- Habrá otro cuadro para decidir cada cuando días se actualiza en mapa cuando la simulación esté corriendo. Por defecto esto será 1.
- Debajo del mapa habrá un slide horizontal que permitirá retrotraerse a cualquier día de la simulación y recuperar como se vería el mapa ese día.
- También habra un boton de "replay" que permita recorrer toda la secuencias de simulaciones actualizando el mapa.

### Dentro de la pestaña "RESULTADOS"

- Dentro de la pestaña de resultados se inclurirán las tablas dhd, dc, con botones en cada una para poder ser descargarlas.

### Dentro de la pestaña "ANALISIS TEMPORAL"

- Un gráfico con la función "dibujar_densidades". Donde se ve la evolución de las densidades (o de una fórmula de estas) de cada hexágono. También quiero que aparezca:
  + Un cuadro de texto donde se pueda poner la fórmula con las densidades
  + Un cuadro de texto dónde pueda poner una explicación de la fórmula.
  + Un boton para el gráfico cuando cambio la formula.
  + Un cuadro numérico para cambiar el dia inicial del gráfico DIAi
  + Un cuadro numérico para cambiar el dia final del gráfico DIAf.
  + Un cuadro fara filtrar por las columnas de los hexágonos que deseamos incluir en el mapa
  + Un cuadro para filtrar por las filas de los heágonos que deseamos incluir en el mapa
  
## Codificación

- Crea el código relativo a la simulación en R y comenta bien las diferentes partes para que yo pueda entender lo que vas haciendo
- La parte del código para crear el interface con el usuario lo puedes hacer del modo más efectivo
