/// Como se llaman los archivos que salen de la app.
///
/// Un solo lugar porque el nombre lo usan tres partes: el archivo en el
/// telefono, la llave en el bucket y el campo `Nombre` de Airtable. Si se
/// arman por separado, el dia que alguien busque el KML en el bucket no lo va
/// a encontrar con el nombre que vio en la base.
///
/// Forma: `<proyecto>-<trazado>-<fecha>.<ext>`, todo en minusculas, sin tildes
/// y sin espacios. Windows, S3 y Google Earth tienen cada uno su lista de
/// caracteres prohibidos; la interseccion segura es `[a-z0-9-]`.
class NombresArchivo {
  // TODO: paraTrazado(proyecto, trazado, ext)
  // TODO: llaveBucket(proyectoCodigo, tipo, nombre)
  //       -> proyectos/<codigo>/kml/<nombre>
}
