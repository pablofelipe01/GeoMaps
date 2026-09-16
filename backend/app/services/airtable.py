"""Escritura en Airtable.

La regla que sostiene todo el modelo offline: **upsert por UUID, nunca create
a ciegas.** Cada tabla tiene su campo `Codigo <entidad>` con el UUID que genero
el telefono antes de tener red. El servicio busca por ese codigo con
`filterByFormula` y decide entre PATCH y POST.

Por que importa: la red movil rural corta a mitad de un POST mas seguido de lo
que parece. Sin el upsert, cada reintento de sincronizacion duplicaria el
trazado, y dos poligonos identicos con areas iguales son imposibles de
distinguir despues.

Dos detalles de la API que cuestan tiempo:

- `typecast: true` deja que Airtable convierta la cadena al tipo del campo. Sin
  el, escribir un Single select con una opcion que no existe falla con un error
  que no dice cual.
- Los adjuntos se cargan por URL: Airtable va el mismo a buscarla desde sus
  servidores. Con el bucket privado eso significa pasarle una **URL prefirmada
  de lectura**. Airtable copia el archivo a su propio almacenamiento al
  escribir, asi que el adjunto sigue funcionando cuando la URL vence. Lo que no
  sobrevive es lo contrario: una URL ya vencida al momento de escribir deja el
  adjunto vacio y Airtable responde 200 igual.

Lo que Airtable guarda de S3 es la **llave**, nunca la URL. La llave es estable;
la URL vence. Una base llena de URLs prefirmadas vencidas es una base de filas
que apuntan a un 403 sin decir por que.
"""

API = "https://api.airtable.com/v0"

# TODO: upsert(settings, tabla, campo_codigo, codigo, fields) -> record_id
# TODO: upsert_lote(...) -- Airtable acepta 10 registros por request
# TODO: listar(settings, tabla, formula) -> paginado con offset
