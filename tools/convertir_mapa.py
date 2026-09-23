# -*- coding: utf-8 -*-
"""Convierte un plano de topografia en una capa que el telefono puede abrir.

Toma el GeoPDF (o GeoTIFF) que mando topografia, lo pasa a MBTiles con GDAL,
sube las dos cosas al bucket y deja la ficha en la tabla `Mapas` en `Listo`.
Desde ese momento la app lo ve en el catalogo y lo puede descargar.

Se corre con el Python del backend, que ya trae boto3 y httpx y lee
`backend/.env`:

    backend/.venv/Scripts/python tools/convertir_mapa.py "plano.pdf" \\
        --proyecto <codigo del proyecto> --nombre "Acopios 2026"

Opciones:

    --proyecto CODIGO  A que proyecto pertenece la capa. Obligatorio.
    --nombre TEXTO     Como se ve en la app. Por defecto, el del archivo.
    --dpi N            Con cuanto detalle se rasteriza el PDF (300).
    --src EPSG:XXXX    Solo si el archivo NO trae su sistema adentro.
    --zoom-max N       Corta el detalle maximo. Sin esto lo decide GDAL.
    --simular          Convierte y mide, pero no sube ni escribe en Airtable.
    --conservar        No borra los intermedios. Para mirar que salio mal.

## Por que esto no corre en el backend

GDAL necesita binarios del sistema, y rasterizar un plano grande son minutos de
CPU y varios GB de temporales. No cabe en una funcion serverless. Mientras sean
unos pocos mapas al mes -que es el caso hoy- esto se corre a mano y la app no
ve ninguna diferencia: para ella un mapa esta `Listo` o no esta.

## Donde encuentra GDAL

En el PATH, o en la instalacion de QGIS, que lo trae completo y con el driver
de PDF. Se puede forzar con la variable `GDAL_BIN`.

El driver de PDF **no** viene en todas las compilaciones de GDAL. Si falta, el
script lo dice al arrancar en vez de fallar a la mitad con un error de formato.

## Las cuatro pasadas de GDAL, y por que son cuatro

1. `gdal_translate` del PDF a GeoTIFF, rasterizando a `--dpi`. El DPI es la
   unica decision irreversible del proceso: es el detalle que va a existir para
   siempre en las teselas. 300 es el punto donde los rotulos de un plano de
   escala 1:10.000 todavia se leen.
2. `gdalwarp` a EPSG:3857. Las teselas del mundo web viven en Web Mercator y
   el plano viene en el sistema del pais -aca MAGNA-SIRGAS-. Este paso es el
   que hace que el plano caiga donde debe.
3. `gdal_translate` a MBTILES. Un solo archivo SQLite en vez de decenas de
   miles de PNG sueltos.
4. `gdaladdo`, las vistas alejadas. **No es opcional**: sin ellas, alejar el
   mapa en el telefono deja la pantalla en blanco, sin ningun error.

## Lo que se niega a hacer

- **Convertir un archivo sin georreferencia.** Un plano sin sistema de
  coordenadas no se puede ubicar; GDAL igual lo convertiria, y quedaria una
  capa que se dibuja en el Atlantico o encima de otra cosa. Si el archivo no la
  trae pero se sabe cual es, se pasa con `--src`.
- **Escribir la ficha sin que los dos objetos esten arriba.** Una fila en
  `Listo` cuyo MBTiles no existe es una descarga que falla en el potrero.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
BACKEND = RAIZ / "backend"

# Las llaves del bucket se arman en un solo lugar, el mismo que van a usar los
# endpoints cuando existan. Dos formas de armar el prefijo es como quedan filas
# apuntando al vacio.
sys.path.insert(0, str(BACKEND))

FORMATOS = {
    ".pdf": "GeoPDF",
    ".tif": "GeoTIFF",
    ".tiff": "GeoTIFF",
}


def fallar(mensaje: str) -> None:
    print(f"\n[X] {mensaje}\n", file=sys.stderr)
    sys.exit(1)


def cargar_env() -> None:
    """Lee backend/.env sin pisar lo que ya este en el entorno."""
    env = BACKEND / ".env"
    if not env.exists():
        fallar("No existe backend/.env: hacen falta AWS y Airtable.")
    for linea in env.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        clave, valor = linea.split("=", 1)
        os.environ.setdefault(clave.strip(), valor.strip().strip('"').strip("'"))


# --- GDAL ----------------------------------------------------------------


def carpeta_gdal() -> Path:
    """Donde estan los ejecutables de GDAL.

    QGIS entra en la busqueda porque es lo que ya esta instalado en las
    maquinas del equipo: trae GDAL completo, con el driver de PDF, y evita
    pedirle a alguien que instale conda solo para convertir un plano.
    """
    forzada = os.environ.get("GDAL_BIN")
    if forzada:
        if not (Path(forzada) / "gdalinfo.exe").exists() and not (
            Path(forzada) / "gdalinfo"
        ).exists():
            fallar(f"GDAL_BIN apunta a {forzada}, pero ahi no hay gdalinfo.")
        return Path(forzada)

    en_path = shutil.which("gdalinfo")
    if en_path:
        return Path(en_path).parent

    candidatos = sorted(
        Path("C:/Program Files").glob("QGIS *"), reverse=True
    ) + sorted(Path("C:/").glob("OSGeo4W*"))
    for base in candidatos:
        if (base / "bin" / "gdalinfo.exe").exists():
            return base / "bin"

    fallar(
        "No se encontro GDAL. Instalalo con conda (ver tools/README.md), o "
        "apunta GDAL_BIN a la carpeta bin de QGIS."
    )
    return Path()


def correr(exe: Path, argumentos: list[str], titulo: str) -> None:
    print(f"  {titulo}...")
    r = subprocess.run([str(exe), *argumentos], capture_output=True, text=True)
    if r.returncode != 0:
        salida = (r.stderr or r.stdout).strip()
        fallar(f"Fallo {exe.name}:\n{salida}")


def informacion(gdal: Path, archivo: Path) -> dict:
    r = subprocess.run(
        [str(gdal / "gdalinfo"), "-json", str(archivo)],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        fallar(f"gdalinfo no pudo leer el archivo:\n{(r.stderr or r.stdout).strip()}")
    return json.loads(r.stdout)


def revisar_driver_pdf(gdal: Path) -> None:
    r = subprocess.run(
        [str(gdal / "gdalinfo"), "--formats"], capture_output=True, text=True
    )
    if " PDF " not in r.stdout:
        fallar(
            "Esta compilacion de GDAL no trae el driver de PDF. Con conda: "
            "`conda install -c conda-forge gdal`, o usa el GDAL de QGIS."
        )


# --- El MBTiles ----------------------------------------------------------


def metadatos_mbtiles(archivo: Path) -> dict[str, str]:
    """`bounds`, `minzoom` y `maxzoom` tal como quedaron escritos.

    Se leen del archivo y no se calculan aparte: lo que importa es lo que el
    telefono va a encontrar adentro, no lo que deberia haber quedado.
    """
    con = sqlite3.connect(f"file:{archivo}?mode=ro", uri=True)
    try:
        filas = con.execute("SELECT name, value FROM metadata").fetchall()
    finally:
        con.close()
    return {n: v for n, v in filas}


def contar_teselas(archivo: Path) -> int:
    con = sqlite3.connect(f"file:{archivo}?mode=ro", uri=True)
    try:
        return con.execute("SELECT count(*) FROM tiles").fetchone()[0]
    finally:
        con.close()


def _metros_por_pixel(zoom: int) -> float:
    """Cuanto mide un pixel en Web Mercator, en el ecuador, a ese zoom.

    40.075.016,686 m de circunferencia repartidos en 256 px por tesela. Es la
    constante con la que estan definidos los niveles de zoom del mundo web.
    """
    return 156543.03392804097 / (2**zoom)


def convertir(
    gdal: Path,
    origen: Path,
    trabajo: Path,
    dpi: int,
    src: str | None,
    zoom_max: int | None,
) -> tuple[Path, Path]:
    """Del archivo de topografia al MBTiles. Devuelve (mbtiles, miniatura)."""
    paso1 = trabajo / "paso1.tif"
    paso2 = trabajo / "paso2.tif"
    mbtiles = trabajo / "mapa.mbtiles"
    miniatura = trabajo / "miniatura.png"

    if origen.suffix.lower() == ".pdf":
        correr(
            gdal / "gdal_translate",
            [
                "-of",
                "GTiff",
                "--config",
                "GDAL_PDF_DPI",
                str(dpi),
                str(origen),
                str(paso1),
            ],
            f"rasterizando el PDF a {dpi} DPI",
        )
    else:
        paso1 = origen

    # `-dstalpha` no es un detalle: el plano viene en el sistema del pais y al
    # reproyectarlo queda girado unos grados, asi que sobran esquinas. Sin
    # banda alfa esas esquinas se rellenan de negro, y como esto es una capa
    # **encima** del satelital, serian cuñas negras tapando el mapa.
    #
    # `-s_srs` solo cuando el archivo no lo trae: pasarlo siempre pisaria el
    # sistema correcto del archivo con el que alguien escribio de memoria.
    warp = ["-t_srs", "EPSG:3857", "-r", "bilinear", "-dstalpha"]
    if src:
        warp = ["-s_srs", src, *warp]
    if zoom_max is not None:
        # El zoom maximo no se pide: se deduce de cuantos metros mide un pixel.
        # El driver de MBTiles no tiene opcion MAXZOOM -la ignora en silencio-,
        # asi que el tope se impone aca, remuestreando a la resolucion exacta
        # de ese nivel.
        warp += ["-tr", str(_metros_por_pixel(zoom_max)), str(_metros_por_pixel(zoom_max))]
    correr(
        gdal / "gdalwarp",
        [*warp, str(paso1), str(paso2)],
        "reproyectando a Web Mercator",
    )

    correr(
        gdal / "gdal_translate",
        ["-of", "MBTILES", "-co", "TYPE=overlay", str(paso2), str(mbtiles)],
        "escribiendo las teselas",
    )

    # Las vistas alejadas. Los factores llegan hasta 32 -cinco niveles- porque
    # es lo que hace falta para que un predio entero entre en la pantalla.
    correr(
        gdal / "gdaladdo",
        ["-r", "average", str(mbtiles), "2", "4", "8", "16", "32"],
        "generando las vistas alejadas",
    )

    correr(
        gdal / "gdal_translate",
        ["-of", "PNG", "-outsize", "480", "0", str(paso2), str(miniatura)],
        "sacando la miniatura",
    )

    return mbtiles, miniatura


# --- Airtable y S3 -------------------------------------------------------


def cliente_s3():
    import boto3

    return boto3.client(
        "s3",
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        region_name=os.environ.get("AWS_REGION", "us-east-1"),
    )


async def fila_proyecto(settings, codigo: str) -> dict:
    from app.services import airtable

    seguro = codigo.replace("'", "")
    fila = await airtable.buscar_uno(
        settings,
        settings.airtable_tabla_proyectos,
        f"OR({{Codigo proyecto}}='{seguro}',{{Nombre}}='{seguro}')",
    )
    if not fila:
        fallar(
            f"No hay ningun proyecto con codigo o nombre '{codigo}'. "
            "La capa tiene que colgar de un proyecto: el bucket se organiza "
            "por proyecto y borrar uno se lleva lo suyo."
        )
    return fila


async def escribir_ficha(settings, codigo_mapa: str, campos: dict) -> None:
    from app.services import airtable

    await airtable.upsert(
        settings,
        settings.airtable_tabla_mapas,
        "Codigo mapa",
        codigo_mapa,
        campos,
    )


# --- Programa ------------------------------------------------------------


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("archivo", help="El GeoPDF o GeoTIFF de topografia")
    p.add_argument("--proyecto", required=True, help="Codigo o nombre del proyecto")
    p.add_argument("--nombre", default=None, help="Como se ve en la app")
    p.add_argument("--dpi", type=int, default=300)
    p.add_argument("--src", default=None, help="Solo si el archivo no lo trae")
    p.add_argument("--zoom-max", type=int, default=None)
    p.add_argument("--simular", action="store_true")
    p.add_argument("--conservar", action="store_true")
    args = p.parse_args()

    origen = Path(args.archivo).expanduser()
    if not origen.exists():
        fallar(f"No existe el archivo {origen}")
    formato = FORMATOS.get(origen.suffix.lower())
    if not formato:
        fallar(
            f"Extension {origen.suffix} no soportada. Este script convierte "
            f"{', '.join(sorted(set(FORMATOS.values())))}."
        )

    cargar_env()
    gdal = carpeta_gdal()
    print(f"GDAL: {gdal}")
    if origen.suffix.lower() == ".pdf":
        revisar_driver_pdf(gdal)

    # Antes de gastar minutos de CPU: si no se sabe donde va, no hay capa.
    info = informacion(gdal, origen)
    src_archivo = (info.get("coordinateSystem") or {}).get("wkt")
    if not src_archivo and not args.src:
        fallar(
            "El archivo no trae sistema de coordenadas: no hay forma de saber "
            "donde va en el mundo. Si sabes cual es, pasalo con --src "
            "(p. ej. --src EPSG:3116 para MAGNA-SIRGAS Bogota)."
        )
    src_origen = args.src or _epsg_legible(gdal, origen, info)
    print(f"Sistema de origen: {src_origen}")

    from app.config import get_settings

    settings = get_settings()

    # Con --simular no se consulta Airtable: la gracia de una prueba en seco es
    # poder medir cuanto pesa y como queda un plano sin depender de que la base
    # ya tenga el proyecto creado, ni dejar rastro de la prueba.
    if args.simular:
        proyecto = None
        codigo_proyecto = "simulacion"
    else:
        proyecto = asyncio.run(fila_proyecto(settings, args.proyecto))
        codigo_proyecto = proyecto["fields"]["Codigo proyecto"]
        print(f"Proyecto: {proyecto['fields'].get('Nombre')} ({codigo_proyecto})")

    codigo_mapa = str(uuid.uuid4())
    nombre = args.nombre or origen.stem

    trabajo = Path(tempfile.mkdtemp(prefix="geomaps-"))
    try:
        print("Convirtiendo:")
        mbtiles, miniatura = convertir(
            gdal, origen, trabajo, args.dpi, args.src, args.zoom_max
        )

        meta = metadatos_mbtiles(mbtiles)
        teselas = contar_teselas(mbtiles)
        tamano_mb = round(mbtiles.stat().st_size / 1_048_576, 1)
        bbox = meta.get("bounds", "")
        zoom_min = int(meta.get("minzoom", 0))
        zoom_max = int(meta.get("maxzoom", 0))

        print(
            f"\nQuedo: {tamano_mb} MB, {teselas} teselas, "
            f"zoom {zoom_min}-{zoom_max}\n  bbox {bbox}"
        )
        if not bbox:
            fallar(
                "El MBTiles quedo sin `bounds`. Sin el, la app no puede "
                "encuadrar ni avisar que estas parado fuera del mapa."
            )

        if args.simular:
            print("\n--simular: no se subio nada ni se escribio en Airtable.")
            return

        from app.services import almacenamiento

        llave = almacenamiento.llave_mapa(codigo_proyecto, codigo_mapa)
        llave_original = almacenamiento.llave_mapa_original(
            codigo_proyecto, codigo_mapa, origen.suffix
        )
        llave_mini = almacenamiento.llave_miniatura_mapa(codigo_proyecto, codigo_mapa)

        s3 = cliente_s3()
        bucket = os.environ["S3_BUCKET"]

        # Primero los objetos, la ficha al final: una fila en `Listo` cuyo
        # MBTiles todavia se esta subiendo es una descarga que falla en campo.
        print("\nSubiendo:")
        for ruta, destino, titulo in (
            (mbtiles, llave, f"MBTiles ({tamano_mb} MB)"),
            (origen, llave_original, "original de topografia"),
            (miniatura, llave_mini, "miniatura"),
        ):
            print(f"  {titulo}...")
            s3.upload_file(str(ruta), bucket, destino)

        url_mini = almacenamiento.url_lectura(settings, llave_mini, ttl=3600)
        ahora = datetime.now(timezone.utc).isoformat()

        asyncio.run(
            escribir_ficha(
                settings,
                codigo_mapa,
                {
                    "Nombre": nombre,
                    "Proyecto": [proyecto["id"]],
                    "Formato origen": formato,
                    "Llave S3": llave,
                    "Llave S3 original": llave_original,
                    "Tamano (MB)": tamano_mb,
                    "SRC origen": src_origen,
                    "Zoom min": zoom_min,
                    "Zoom max": zoom_max,
                    "Bbox": bbox,
                    # Airtable copia el binario desde la URL prefirmada en el
                    # momento de escribir; por eso la URL puede vencer despues.
                    "Miniatura": [{"url": url_mini, "filename": f"{nombre}.png"}],
                    "Estado": "Listo",
                    "Creado en": ahora,
                },
            )
        )
        print(f"\n[ok] Ficha escrita. Codigo mapa: {codigo_mapa}")
        print("La app lo va a ver en el catalogo del proyecto.")
    finally:
        if args.conservar:
            print(f"Intermedios en {trabajo}")
        else:
            shutil.rmtree(trabajo, ignore_errors=True)


def _epsg_legible(gdal: Path, archivo: Path, info: dict) -> str:
    """`EPSG:3116` si se puede; si no, el nombre del sistema.

    Lo resuelve `gdalsrsinfo -e`, que **identifica** el sistema contra la base
    de EPSG aunque el archivo no traiga el codigo adentro -que es justo el caso
    de los GeoPDF de topografia, cuyo WKT no lo lleva-. Sacarlo a mano del WKT
    no sirve: el ultimo `ID["EPSG",N]` que aparece suele ser el de la unidad
    (9001, metro), no el del sistema.

    Se guarda en `SRC origen` porque es el campo que mas caro sale olvidar: un
    plano en MAGNA-SIRGAS interpretado como WGS84 abre sin error y se dibuja
    cientos de metros corrido.
    """
    r = subprocess.run(
        [str(gdal / "gdalsrsinfo"), "-e", str(archivo)],
        capture_output=True,
        text=True,
    )
    primera = (r.stdout or "").strip().splitlines()
    if primera:
        codigo = primera[0].strip()
        # Sin match devuelve `EPSG:0`, que como dato es peor que el nombre.
        if codigo.startswith("EPSG:") and codigo != "EPSG:0":
            return codigo

    wkt = (info.get("coordinateSystem") or {}).get("wkt", "")
    nombre = wkt.split('"')[1] if '"' in wkt else ""
    return nombre or "desconocido"


if __name__ == "__main__":
    main()
