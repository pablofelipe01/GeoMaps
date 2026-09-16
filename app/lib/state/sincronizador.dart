/// Sube a Airtable lo que se hizo sin senal.
///
/// Corre cuando hay red y hay filas con `sincronizado = false`. El orden no es
/// arbitrario: Airtable necesita los enlaces resueltos, asi que un waypoint no
/// puede subir antes que su proyecto.
///
///   Proyectos -> Mapas -> Trazados -> Waypoints -> Archivos -> Sincronizaciones
///
/// Cada paso es un upsert por UUID. Si el tercero falla, los dos primeros ya
/// quedaron y el reintento no los duplica. Cada intento deja una fila en
/// `Sincronizaciones`, que es lo que permite explicar despues un dato que
/// alguien dice que no aparece.
class Sincronizador {
  // TODO: sincronizar() -> ResumenSync(enviados, fallidos, detalle)
}
