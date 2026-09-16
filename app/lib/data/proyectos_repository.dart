/// Lectura y escritura de proyectos en la base local.
///
/// El espejo del directorio que baja de `GET /v1/proyectos` se mezcla con lo
/// que ya tiene el telefono con la regla **rellenar, no pisar**: lo que el
/// tecnico acaba de teclear puede ser mas nuevo que lo que hay en Airtable.
class ProyectosRepository {
  // TODO: listar({soloActivos})
  // TODO: crear(nombre, cliente, municipio) -> genera el UUID
  // TODO: mezclarDirectorio(List<ProyectoRemoto>)
}
