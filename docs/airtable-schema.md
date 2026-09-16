# Base de datos Airtable — GeoMaps

Base sugerida: **Sirius GeoMaps** (crear aparte de `Sirius Agro App`; el
telefono de GeoMaps no tiene por que poder escribir visitas agronomicas).

Convenciones, las mismas del resto de los proyectos Sirius:

- Nombres de campo **sin tildes ni ñ**.
- Fechas ISO (`YYYY-MM-DD`), horas en `America/Bogota`.
- Todo registro creado desde el telefono trae un **UUID generado offline**. El
  backend hace *upsert* contra ese UUID, nunca `create` a ciegas: reintentar
  una sincronizacion no puede duplicar un trazado.
- Los archivos **no** viven en Airtable. Van a **S3** y Airtable guarda la
  `Llave S3` + `Tamano (MB)`. Eso incluye los binarios pesados (MBTiles) y
  tambien la geometria de los trazados, que es texto pero crece sin techo.
- Airtable guarda **punteros y resumenes**, nunca el dato completo cuando el
  dato completo puede crecer. Ver [Que va en S3 y que en Airtable](#que-va-en-s3-y-que-en-airtable).

## Flujo que soporta el modelo

```
USUARIO -> PROYECTO -> MAPA (capa base offline)
                    -> TRAZADO (ruta / poligono)  -> ARCHIVO (KML, GPX, PDF)
                    -> WAYPOINT                   -> FOTO
        -> SINCRONIZACION (log de cada subida)
```

## Tablas

| Tabla | Para que sirve |
|---|---|
| `Usuarios` | Quien usa la app y con que permiso |
| `Dispositivos` | Que telefono tiene que copia de que mapa |
| `Proyectos` | Agrupador: un predio, un municipio, un contrato |
| `Mapas` | Ficha de cada capa base offline (MBTiles) |
| `Trazados` | Rutas y poligonos capturados en campo |
| `Waypoints` | Puntos marcados |
| `Archivos` | Todo lo que la app genera: KML, GPX, PDF, fotos |
| `Sincronizaciones` | Log de cada subida, para poder explicar un dato perdido |

---

### `Usuarios`

| Campo | Tipo | Nota |
|---|---|---|
| `Codigo usuario` | Single line text | UUID. Clave del upsert |
| `Nombre completo` | Single line text | |
| `Documento` | Single line text | Identidad real de la persona |
| `Correo` | Email | |
| `Rol` | Single select | `Campo` / `Coordinador` / `Admin` |
| `Activo` | Checkbox | Desmarcarlo bloquea el login en el siguiente arranque con red |
| `Ultimo acceso` | Date with time | |
| `Dispositivos` | Link -> Dispositivos | |
| `Proyectos` | Link -> Proyectos | Que proyectos puede descargar |

**El password no vive aqui.** Igual que en `sirius_agro`, el login valida
contra Sirius Nomina Core con un PAT de solo lectura y la app guarda un hash
`bcrypt` local para poder entrar sin senal hasta `DIAS_MAX_OFFLINE`. Esta tabla
es el registro de *quien usa GeoMaps*, no un almacen de credenciales.

### `Dispositivos`

| Campo | Tipo | Nota |
|---|---|---|
| `Codigo dispositivo` | Single line text | UUID que genera la app en el primer arranque |
| `Usuario` | Link -> Usuarios | |
| `Modelo` | Single line text | |
| `Version app` | Single line text | `1.0.0+1` |
| `Almacenamiento libre (GB)` | Number | Lo reporta la app al sincronizar. Sirve para saber a quien no le cabe un mapa nuevo |
| `Mapas descargados` | Link -> Mapas | |
| `Ultima sincronizacion` | Date with time | |

Existe por una pregunta operativa concreta: *el tecnico que va manana al lote 7,
tiene el mapa nuevo en el telefono?* Sin esta tabla la respuesta es llamarlo.

### `Proyectos`

| Campo | Tipo | Nota |
|---|---|---|
| `Codigo proyecto` | Single line text | UUID |
| `Nombre` | Single line text | |
| `Cliente` | Single line text | |
| `Municipio` | Single line text | |
| `Centro lat` / `Centro lon` | Number (precision 6) | Donde abre el mapa |
| `Estado` | Single select | `Activo` / `Cerrado` |
| `Mapas` | Link -> Mapas | |
| `Trazados` | Link -> Trazados | |
| `Usuarios` | Link -> Usuarios | |

### `Mapas`

La ficha de una capa base offline. **El MBTiles no se adjunta**: se sube al
bucket y aqui queda la URL.

| Campo | Tipo | Nota |
|---|---|---|
| `Codigo mapa` | Single line text | UUID |
| `Nombre` | Single line text | |
| `Proyecto` | Link -> Proyectos | |
| `Formato origen` | Single select | `GeoPDF` / `GeoTIFF` / `KMZ` / `MBTiles` |
| `Llave S3` | Single line text | Del MBTiles ya convertido |
| `Llave S3 original` | Single line text | Del archivo que mando topografia, tal como llego. Se conserva para poder reconvertir con otros parametros sin volver a pedirlo |
| `Tamano (MB)` | Number (1 decimal) | La app lo muestra antes de descargar |
| `SRC origen` | Single line text | EPSG del archivo que mando topografia, p. ej. `EPSG:3116` (MAGNA-SIRGAS Bogota) |
| `Zoom min` / `Zoom max` | Number | |
| `Bbox` | Long text | `minLon,minLat,maxLon,maxLat` en WGS84 |
| `Miniatura` | Attachment | Lo unico binario que si va en Airtable |
| `Estado` | Single select | `Procesando` / `Listo` / `Fallido` |
| `Error` | Long text | Que dijo GDAL cuando fallo |
| `Subido por` | Link -> Usuarios | |
| `Creado en` | Date with time | |

`SRC origen` esta porque es el campo que mas caro sale olvidar: un plano en
MAGNA-SIRGAS interpretado como WGS84 se dibuja unos cientos de metros corrido,
abre sin error, y nadie lo nota hasta que alguien camina al punto equivocado.

### `Trazados`

| Campo | Tipo | Nota |
|---|---|---|
| `Codigo trazado` | Single line text | UUID generado en campo |
| `Nombre` | Single line text | |
| `Proyecto` | Link -> Proyectos | |
| `Tipo` | Single select | `Ruta` / `Poligono` |
| `Llave geometria` | Single line text | Llave S3 del GeoJSON completo: `proyectos/<codigo>/geometrias/<codigo trazado>.geojson`. **Es la geometria de verdad** |
| `Bbox` | Single line text | `minLon,minLat,maxLon,maxLat`. Permite filtrar por zona sin bajar el archivo |
| `Centro lat` / `Centro lon` | Number (precision 6) | Centroide. Es lo que hace que una fila de Airtable se pueda abrir en Google Maps de un clic |
| `Vista previa` | Long text | GeoJSON **simplificado** a un maximo de 50 vertices. No es el dato: es para ver la forma sin salir de Airtable |
| `Puntos` | Number | Cuantos vertices tiene el archivo real |
| `Distancia (m)` | Number (1 decimal) | |
| `Area (ha)` | Number (4 decimales) | Solo poligonos. Calculada con el radio WGS84 de `core/geo.dart`, el mismo que usa Google Earth |
| `Precision media (m)` | Number (1 decimal) | Que tan bueno era el GPS. Un poligono levantado bajo arboles con 30 m de error no sirve para un lindero |
| `Metodo` | Single select | `Automatico` / `Manual` / `Mixto` |
| `Iniciado en` / `Terminado en` | Date with time | |
| `Capturado por` | Link -> Usuarios | |
| `Archivos` | Link -> Archivos | Sus KML/GPX/PDF |
| `Waypoints` | Link -> Waypoints | |

**La geometria vive en S3, no en Airtable.** El `Long text` de Airtable tope en
100.000 caracteres: un recorrido de 800 vertices entra (unos 20 KB), pero una
jornada completa grabada cada 5 segundos son decenas de miles de puntos y no
entra. El limite se alcanza sin aviso util, y el trazado que lo cruza es
justamente el que mas trabajo costo levantar.

Lo que **si** queda en Airtable es lo que hace consultable la fila sin bajar
nada: `Bbox`, el centroide, el conteo de puntos y una `Vista previa`
simplificada. Esa distincion importa por la premisa del proyecto — coordinacion
abre la base y ve que se levanto esta semana. Si la fila fuera solo una llave de
S3, Airtable dejaria de servir para mirar y quedaria como un indice ciego.

La `Vista previa` se genera con Douglas-Peucker hasta 50 vertices. Es
deliberadamente **no** el dato: nadie puede medir un area sobre ella. Por eso se
llama asi y no `Geometria`.

### `Waypoints`

| Campo | Tipo | Nota |
|---|---|---|
| `Codigo waypoint` | Single line text | UUID |
| `Nombre` | Single line text | |
| `Proyecto` | Link -> Proyectos | |
| `Trazado` | Link -> Trazados | Opcional |
| `Latitud` / `Longitud` | Number (precision 6) | |
| `Altitud (m)` | Number (1 decimal) | |
| `Precision (m)` | Number (1 decimal) | |
| `Simbolo` | Single select | `Generico` / `Muestra` / `Arbol` / `Fuente de agua` / `Infraestructura` / `Riesgo` |
| `Nota` | Long text | |
| `Fotos` | Link -> Archivos | |
| `Marcado en` | Date with time | Hora del GPS, no la del telefono |
| `Marcado por` | Link -> Usuarios | |

### `Archivos`

Todo lo que la app **genera**. Una fila por entregable.

| Campo | Tipo | Nota |
|---|---|---|
| `Codigo archivo` | Single line text | UUID |
| `Nombre` | Single line text | Como se llama en el bucket |
| `Tipo` | Single select | `KML` / `KMZ` / `GPX` / `GeoJSON` / `PDF` / `Foto` |
| `Llave S3` | Single line text | Donde esta en el bucket |
| `Adjunto` | Attachment | Airtable lo copia desde una URL prefirmada al momento de escribir. Solo para PDF y fotos: sirve para verlo en la base sin descargar nada |
| `Tamano (MB)` | Number (1 decimal) | |
| `Proyecto` | Link -> Proyectos | |
| `Trazado` | Link -> Trazados | |
| `Waypoint` | Link -> Waypoints | |
| `Generado en` | Date with time | |
| `Generado por` | Link -> Usuarios | |

Las fotos se guardan bajo el prefijo del proyecto
(`proyectos/<codigo>/fotos/<uuid>.jpg`) por la misma razon que en `sirius_agro`:
borrar el proyecto tiene que llevarse sus archivos.

### `Sincronizaciones`

| Campo | Tipo | Nota |
|---|---|---|
| `Codigo sync` | Single line text | UUID del intento |
| `Dispositivo` | Link -> Dispositivos | |
| `Usuario` | Link -> Usuarios | |
| `Inicio` / `Fin` | Date with time | |
| `Registros enviados` | Number | |
| `Registros fallidos` | Number | |
| `Estado` | Single select | `Ok` / `Parcial` / `Fallida` |
| `Detalle` | Long text | Que fallo y por que |

Existe para poder responder *el trazado del martes no aparece* sin adivinar.

---

## Que va en S3 y que en Airtable

La linea divisoria no es *binario vs. texto*, es **si el dato puede crecer sin
techo**. Un GeoJSON es texto plano y aun asi va a S3, porque un recorrido de
jornada completa no cabe en un `Long text`.

| Dato | Donde | Por que |
|---|---|---|
| MBTiles | S3 | Cientos de MB |
| Original de topografia (GeoPDF/GeoTIFF) | S3 | Pesado, y se conserva para reconvertir |
| GeoJSON del trazado | S3 | Crece con los vertices, sin techo |
| KML / KMZ / GPX / PDF | S3 | Entregables, pueden pesar |
| Fotos | S3 | Binario |
| Miniatura del mapa | Airtable (Attachment) | Unos KB, y es lo que hace legible la tabla |
| PDF y fotos, ademas | Airtable (Attachment) | Copia para poder verlos en la base. S3 sigue siendo el original |
| Bbox, centroide, area, distancia, conteo, precision | Airtable | Tamano fijo, y es lo que se consulta y se filtra |
| Vista previa simplificada | Airtable | 50 vertices como maximo. Para ver la forma, no para medir |

### Estructura del bucket

Todo cuelga del proyecto. No es cosmetica: borrar un proyecto tiene que poder
llevarse **todo** lo suyo con un solo `delete` por prefijo, sin ir a buscar
archivos sueltos por otras carpetas.

```
s3://sirius-geomaps/
  proyectos/<codigo proyecto>/
    mapas/<codigo mapa>.mbtiles
    mapas/originales/<codigo mapa>.pdf
    geometrias/<codigo trazado>.geojson
    kml/<nombre>.kml
    gpx/<nombre>.gpx
    pdf/<nombre>.pdf
    fotos/<codigo waypoint>/<uuid>.jpg
```

### Como se lee un trazado completo

1. Airtable da la fila: nombre, area, precision, `Llave geometria`.
2. El backend firma una URL de lectura de esa llave (`GET`, TTL corto).
3. Quien consulta baja el GeoJSON.

El telefono **no** hace ese viaje para trabajar: su copia local en SQLite tiene
la geometria completa y es la fuente de verdad mientras esta en campo. El
archivo de S3 es para el resto del mundo.

### Acceso a S3

El bucket es **privado**. Nada se sirve publico:

- La app sube con una **URL prefirmada de escritura** que pide al backend. Asi
  el telefono nunca tiene credenciales de AWS adentro del APK.
- La app descarga mapas con una **URL prefirmada de lectura**, con TTL largo
  (una descarga de 400 MB sobre red rural tarda).
- Airtable recibe una prefirmada de lectura solo para los `Attachment`. Airtable
  **copia** el archivo a su propio almacenamiento al momento de escribir, asi
  que el adjunto sigue funcionando despues de que la URL expire.

---

## Reglas que aplica el backend, no el modelo

1. **Upsert por UUID, siempre.** Buscar por `Codigo X` y actualizar si existe.
   La red movil rural corta a mitad de un POST mas seguido de lo que parece.
2. **Un trazado sin `Precision media` no se marca como apto para lindero.** El
   dato existe, pero la app lo muestra con aviso.
3. **`Area (ha)` la calcula el telefono, no Airtable.** Si la recalcula el
   backend con otra formula, el numero del papel y el de la base no coinciden y
   ninguno de los dos es creible.
4. **Un `Mapa` en estado `Procesando` no se le ofrece al telefono.** Descargar
   un MBTiles a medio escribir deja la app con un mapa corrupto y sin error.
5. **Primero S3, despues Airtable.** El GeoJSON se sube y se confirma ANTES de
   escribir la fila del trazado. Al reves, una fila con `Llave geometria`
   apuntando a un objeto que no existe es un trazado que en la base parece estar
   y al abrirlo no esta — peor que no tenerlo.
6. **La `Llave geometria` no se reescribe: se versiona.** Editar un trazado
   escribe `<codigo>.geojson` de nuevo con versionado de S3 activo. Sobrescribir
   sin versiones deja sin forma de recuperar un lindero que alguien borro por
   error, y eso en campo no se puede volver a levantar sin caminarlo otra vez.
