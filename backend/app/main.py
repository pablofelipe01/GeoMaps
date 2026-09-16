"""Puntos de entrada HTTP.

Todos piden `X-API-Key` salvo `/health`.

Lo que este backend hace y lo que no:

- **Hace**: guardar las llaves, convertir mapas a MBTiles, firmar URLs del
  bucket y escribir en Airtable con upsert por UUID.
- **No hace**: ser necesario para trabajar. La app funciona completa con este
  servicio caido; lo unico que no puede es sincronizar ni bajar mapas nuevos.
"""

# TODO: GET  /health
# TODO: POST /v1/login             valida contra nomina, devuelve hash bcrypt
# TODO: GET  /v1/proyectos         espejo del directorio para la app
# TODO: GET  /v1/mapas             fichas de mapas en estado Listo
# TODO: GET  /v1/mapas/{id}/descarga   URL firmada del MBTiles
# TODO: POST /v1/mapas             sube el original y encola la conversion
# TODO: POST /v1/archivos          sube KML/GPX/PDF/foto al bucket
# TODO: POST /v1/sync              upsert por UUID de todo lo pendiente
