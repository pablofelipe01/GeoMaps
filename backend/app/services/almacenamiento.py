"""AWS S3: donde vive todo lo que puede crecer.

La linea divisoria con Airtable no es binario vs. texto, es **si el dato tiene
techo**. Un GeoJSON es texto plano y aun asi vive aca, porque una jornada
grabada cada 5 segundos son decenas de miles de vertices y el `Long text` de
Airtable topa en 100.000 caracteres.

Airtable guarda la `Llave S3`, no la URL. La llave es estable; la URL es
prefirmada y vence. Guardar una URL vencida en la base produce filas que
apuntan a un 403 y nadie sabe por que.

## Estructura

Todo cuelga del proyecto, para que borrarlo sea un solo delete por prefijo y no
una caceria de archivos sueltos:

    proyectos/<codigo proyecto>/
      mapas/<codigo mapa>.mbtiles
      mapas/originales/<codigo mapa>.pdf
      geometrias/<codigo trazado>.geojson
      kml/<nombre>.kml
      gpx/<nombre>.gpx
      pdf/<nombre>.pdf
      fotos/<codigo waypoint>/<uuid>.jpg

La unica excepcion es el APK de la app, que no es de ningun proyecto:

    app/
      version.json                  el manifiesto de la version vigente
      geomaps-<nombre>+<code>.apk   uno por version publicada

## El bucket es privado

Nada se sirve publico. El telefono nunca tiene credenciales de AWS adentro del
APK: pide una URL prefirmada al backend y sube o baja contra ella.

- **Escritura**: prefirmada de PUT, TTL corto.
- **Lectura**: prefirmada de GET, TTL largo (una descarga de 400 MB sobre red
  rural tarda; si vence a mitad, la reanudacion reintenta contra una URL
  muerta).
- **Airtable**: recibe una prefirmada de lectura solo para los `Attachment`.
  Airtable **copia** el archivo a su propio almacenamiento al escribir, asi que
  el adjunto sobrevive a la expiracion de la URL.

## Configuracion del bucket que no es opcional

1. **Versionado activo.** Editar un trazado reescribe su `.geojson`. Sin
   versiones, un lindero borrado por error no se recupera sin volver a
   caminarlo.
2. **Block Public Access activo.** Si algo tiene que salir a internet, sale
   prefirmado o por CloudFront, nunca por un ACL publico.
3. **Cifrado en reposo (SSE-S3).** Un plano de predio con linderos es dato de
   un cliente.
4. **Regla de ciclo de vida sobre `mapas/originales/`**: a Glacier a los 90
   dias. El GeoPDF original se guarda para poder reconvertir, no para
   consultarlo, y es lo mas pesado que hay en el bucket.
"""

from __future__ import annotations

from functools import lru_cache

import boto3
from botocore.config import Config as BotoConfig
from botocore.exceptions import ClientError

from ..config import Settings


@lru_cache
def _cliente(access_key: str, secret_key: str, region: str):
    """Un cliente por proceso. Los timeouts son cortos porque esto corre dentro
    de un request: un S3 lento no puede colgar la respuesta al telefono."""
    return boto3.client(
        "s3",
        aws_access_key_id=access_key or None,
        aws_secret_access_key=secret_key or None,
        region_name=region,
        config=BotoConfig(
            connect_timeout=3,
            read_timeout=5,
            retries={"max_attempts": 2},
            signature_version="s3v4",
        ),
    )


def cliente(settings: Settings):
    return _cliente(
        settings.aws_access_key_id,
        settings.aws_secret_access_key,
        settings.aws_region,
    )


def leer(settings: Settings, llave: str) -> bytes | None:
    """El contenido de un objeto, o None si no existe. Cualquier otro error
    (credenciales, red) se propaga: no es lo mismo que "no hay nada"."""
    try:
        r = cliente(settings).get_object(Bucket=settings.s3_bucket, Key=llave)
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") in ("NoSuchKey", "404"):
            return None
        raise
    return r["Body"].read()


def url_lectura(settings: Settings, llave: str, ttl: int | None = None) -> str:
    """URL prefirmada de GET. Se arma localmente, sin llamar a AWS."""
    return cliente(settings).generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.s3_bucket, "Key": llave},
        ExpiresIn=ttl or settings.s3_ttl_lectura,
    )


# TODO: url_escritura(llave, content_type) -> URL prefirmada PUT
# TODO: subir(bytes, llave, content_type) -> llave  (para lo que arma el backend)
# TODO: borrar_prefijo(prefijo) -- al eliminar un proyecto
# TODO: existe(llave) -> bool
#       Lo usa sincronizacion.py antes de escribir la fila en Airtable: una
#       `Llave geometria` que apunta a un objeto inexistente es un trazado que
#       en la base parece estar y al abrirlo no esta.


def llave_geometria(codigo_proyecto: str, codigo_trazado: str) -> str:
    """Donde vive el GeoJSON de un trazado.

    Un solo lugar arma esta cadena porque la usan tres partes: el que sube, el
    campo `Llave geometria` de Airtable y el que consulta. Si se arman por
    separado, el dia que cambie el prefijo quedan filas apuntando al vacio.
    """
    return f"proyectos/{codigo_proyecto}/geometrias/{codigo_trazado}.geojson"


def llave_mapa(codigo_proyecto: str, codigo_mapa: str) -> str:
    """El MBTiles que descarga el telefono."""
    return f"proyectos/{codigo_proyecto}/mapas/{codigo_mapa}.mbtiles"


def llave_mapa_original(
    codigo_proyecto: str, codigo_mapa: str, extension: str
) -> str:
    """El archivo tal como lo mando topografia.

    Se conserva para poder reconvertir con otros parametros -mas DPI, otro
    remuestreo- sin volver a pedirselo a nadie. La extension viaja como
    parametro porque el original puede ser PDF, TIFF o KMZ y perderla obliga a
    adivinar el formato al releerlo.
    """
    ext = extension.lower().lstrip(".")
    return f"proyectos/{codigo_proyecto}/mapas/originales/{codigo_mapa}.{ext}"


def llave_miniatura_mapa(codigo_proyecto: str, codigo_mapa: str) -> str:
    """La imagen chica que Airtable copia al campo `Miniatura`.

    Vive en S3 y no solo en Airtable porque Airtable guarda una copia, no el
    original: si alguien borra el adjunto, sin esto habria que reconvertir el
    mapa entero para recuperar una imagen de 40 KB.
    """
    return f"proyectos/{codigo_proyecto}/mapas/miniaturas/{codigo_mapa}.png"
