# Arquitectura

## El principio que ordena todo: el potrero no tiene senal

Cada decision de abajo sale de la misma regla. **Nada de lo que el tecnico hace
en campo puede depender de una respuesta del servidor.** El backend existe para
guardar llaves, convertir mapas pesados y publicar en Airtable — tres cosas que
pueden esperar a que haya cobertura.

Consecuencias directas:

- SQLite local es la **fuente de verdad** mientras la visita ocurre.
- Airtable es el **registro**, no la base operativa.
- Todo id lo genera el telefono (UUID v4), no Airtable.
- La app arranca y funciona con el backend caido.

## Las tres capas

```
┌─────────────────────────── TELEFONO (Flutter) ────────────────────────────┐
│  ui/      pantallas                                                        │
│  state/   Riverpod: lo que la pantalla necesita saber                      │
│  data/    Drift (SQLite) + repositorios + sincronizador                    │
│  core/    geometria, MBTiles, KML/GPX, GPS, cliente HTTP                   │
└────────────────────────────────┬───────────────────────────────────────────┘
                                 │ HTTPS + X-API-Key   (solo cuando hay red)
┌────────────────────────────────▼───────────────────────────────────────────┐
│  backend/ FastAPI en Vercel                                                │
│    services/teselas.py       GeoPDF/GeoTIFF -> MBTiles (llama a GDAL)      │
│    services/almacenamiento.py  firma URLs de S3 (subida y descarga)                │
│    services/airtable.py      upsert por UUID                               │
│    services/nomina.py        login contra Sirius Nomina Core               │
└──────────┬──────────────────────────────┬──────────────────────────────────┘
           │                              │
    ┌──────▼────────┐             ┌───────▼─────────┐
    │  AWS S3 privado│             │    Airtable     │
    │  MBTiles       │             │  llaves S3      │
    │  geometrias    │             │  bbox, area,    │
    │  KML, GPX, PDF │             │  precision,     │
    │  fotos         │             │  vista previa   │
    └────────────────┘             └─────────────────┘
```

## Por que el backend convierte los mapas y no el telefono

Un GeoPDF de topografia trae vectores, capas y una matriz de georreferenciacion
en un SRC local (en Colombia casi siempre MAGNA-SIRGAS). Convertirlo a teselas
es trabajo de GDAL: reproyectar, rasterizar y cortar en piramide. Eso no corre
en un telefono, y aunque corriera, dejarlo correr media hora quemando bateria en
un lote es la peor version posible.

El flujo es: coordinacion sube el mapa desde la web -> el backend lo convierte y
lo deja como MBTiles en el bucket -> el telefono lo descarga una vez, con wifi,
antes de salir a campo.

`tools/` guarda los comandos de GDAL para poder correr la conversion a mano
cuando el archivo es tan grande que no pasa por el endpoint.

## Por que MBTiles y no una carpeta de teselas

Un mapa de un municipio son decenas de miles de archivos `.png` de 10 KB.
Android tarda mas en abrir 40.000 archivos sueltos que en leer un SQLite de
400 MB, y copiar esa carpeta entre telefonos es inviable. MBTiles es un solo
archivo: se descarga, se verifica su tamano, y o esta completo o no esta.

## Reproyeccion: donde se decide

`core/proyeccion.dart` solo se usa para **leer metadatos** y avisar. Las teselas
del MBTiles ya salen del backend en Web Mercator (EPSG:3857), porque es lo que
`flutter_map` sabe dibujar. `proj4dart` esta en el telefono para el caso
contrario: cuando el usuario teclea una coordenada en el SRC del proyecto y hay
que llevarla a WGS84 para ponerla en el mapa.

## Sincronizacion

`state/sincronizador.dart` corre cuando `connectivity_plus` reporta red y hay
registros con `sincronizado = false`. Sube en este orden, porque Airtable
necesita los enlaces resueltos:

```
Proyectos -> Mapas -> Trazados -> Waypoints -> Archivos -> Sincronizaciones
```

Cada paso es un upsert por UUID. Si el tercero falla, los dos primeros ya
quedaron y el reintento no los duplica.

## Lo que se porta de sirius_agro sin tocar

| Archivo | Que trae |
|---|---|
| `core/geo.dart` | Haversine y area de poligono sobre WGS84, con el mismo radio que usa Google Earth. Ya tiene pruebas |
| `core/kml.dart` | KML 2.2 escrito a mano, con el orden `lon,lat,alt` que cuesta una tarde si se olvida |
| `core/ubicacion.dart` | GPS con filtro de precision y de distancia minima |
| `state/red.dart` | Indicador de conectividad |
| `ui/theme.dart`, `ui/marca.dart` | Museo Slab y la marca Sirius |

Se copian, no se importan: son dos apps con ciclos de vida distintos y una
dependencia cruzada entre repos privados haria que un cambio en agro rompa
GeoMaps sin aviso.
