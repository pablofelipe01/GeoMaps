"""El endpoint POST /v1/sync: recibe todo lo que el telefono hizo sin senal.

Orden de escritura, que no es arbitrario porque Airtable necesita los enlaces
resueltos:

    Proyectos -> Mapas -> Trazados -> Waypoints -> Archivos -> Sincronizaciones

Lo que devuelve importa tanto como lo que escribe: por cada UUID enviado, si
quedo o no y por que. El telefono marca `sincronizado = true` solo los que el
backend confirmo, asi que una subida a medias reintenta exactamente lo que
falto y nada mas.
"""

# TODO: sincronizar(settings, payload) -> ResultadoSync
