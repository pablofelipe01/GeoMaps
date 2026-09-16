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

# TODO: url_escritura(llave, content_type) -> URL prefirmada PUT
# TODO: url_lectura(llave, ttl=None) -> URL prefirmada GET
# TODO: subir(bytes, llave, content_type) -> llave  (para lo que arma el backend)
# TODO: leer(llave) -> bytes  (para servir una geometria a quien consulta)
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
