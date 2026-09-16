import 'package:drift/drift.dart';

/// El esquema local. Es la fuente de verdad mientras el telefono esta en campo;
/// Airtable es el registro al que esto se sincroniza despues.
///
/// Dos columnas se repiten en casi todas las tablas y sostienen todo el modelo
/// offline:
///
/// - `codigo`: el UUID que genera el telefono ANTES de tener red. Es la clave
///   del upsert contra Airtable. Sin el, reintentar una sincronizacion cortada
///   duplica el trazado.
/// - `sincronizado`: si la fila ya llego a Airtable. El sincronizador solo
///   mira las que estan en false, asi que una subida a medias no reenvia lo
///   que ya paso.

mixin Sincronizable on Table {
  /// UUID v4 generado en el telefono. Unico de verdad, no autoincremental:
  /// dos telefonos sin red generarian ambos el id 1 y se pisarian al subir.
  TextColumn get codigo => text().unique()();

  BoolColumn get sincronizado => boolean().withDefault(const Constant(false))();
  DateTimeColumn get creadoEn => dateTime()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

class Usuarios extends Table with Sincronizable {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombreCompleto => text()();
  TextColumn get documento => text()();
  TextColumn get correo => text().nullable()();
  TextColumn get rol => text()();

  /// Hash bcrypt de la contrasena, para poder entrar sin senal. La contrasena
  /// en claro no se guarda nunca y el hash lo entrega el backend al validar
  /// contra nomina.
  TextColumn get hashPassword => text().nullable()();

  /// Ultima vez que el login se valido CON red. Pasados los dias de
  /// `Config.diasMaxOffline` la app exige conexion: es lo unico que ve si la
  /// persona sigue activa en nomina.
  DateTimeColumn get validadoEn => dateTime().nullable()();
}

class Proyectos extends Table with Sincronizable {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text()();
  TextColumn get cliente => text().nullable()();
  TextColumn get municipio => text().nullable()();
  RealColumn get centroLat => real().nullable()();
  RealColumn get centroLon => real().nullable()();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
}

class Mapas extends Table with Sincronizable {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get proyectoCodigo => text()();
  TextColumn get nombre => text()();
  TextColumn get formatoOrigen => text()();

  /// Llave del MBTiles en S3. La URL no se guarda: es prefirmada y vence, asi
  /// que se pide al backend en el momento de descargar.
  TextColumn get llaveS3 => text().nullable()();

  /// Donde quedo en el telefono, si ya se descargo. Null = no esta bajado.
  TextColumn get rutaLocal => text().nullable()();

  RealColumn get tamanoMb => real().nullable()();

  /// EPSG del archivo original que mando topografia. Se guarda aunque las
  /// teselas ya vengan en 3857: es lo que permite reproyectar una coordenada
  /// que alguien teclee en el sistema del proyecto.
  TextColumn get srcOrigen => text().nullable()();

  IntColumn get zoomMin => integer().nullable()();
  IntColumn get zoomMax => integer().nullable()();

  /// `minLon,minLat,maxLon,maxLat` en WGS84. Sirve para encuadrar y para
  /// avisar cuando el usuario esta parado fuera del mapa que abrio.
  TextColumn get bbox => text().nullable()();

  TextColumn get estado => text()();

  /// Orden de dibujo, opacidad y visibilidad de la capa. Viven aca y no en el
  /// estado de la pantalla porque el tecnico las ajusta una vez y espera
  /// encontrarlas asi al dia siguiente.
  IntColumn get orden => integer().withDefault(const Constant(0))();
  RealColumn get opacidad => real().withDefault(const Constant(1.0))();
  BoolColumn get visible => boolean().withDefault(const Constant(true))();
}

class Trazados extends Table with Sincronizable {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get proyectoCodigo => text()();
  TextColumn get nombre => text()();
  TextColumn get tipo => text()();
  TextColumn get metodo => text()();

  /// Los vertices como GeoJSON, **completos**. En el telefono la geometria si
  /// vive adentro de la fila: aca no hay limite de 100.000 caracteres y el
  /// SQLite local es la fuente de verdad mientras se esta en campo. Partirla en
  /// una tabla de puntos haria que cada refresco del mapa rearme 800 filas.
  TextColumn get geometria => text()();

  /// Llave del mismo GeoJSON en S3, una vez subido. Null = todavia no salio del
  /// telefono. Es lo que se escribe en el campo `Llave geometria` de Airtable;
  /// la URL no se guarda porque es prefirmada y vence.
  TextColumn get llaveGeometria => text().nullable()();

  /// `minLon,minLat,maxLon,maxLat`. Se calcula al cerrar el trazado y se sube a
  /// Airtable para poder filtrar por zona sin bajar el archivo de S3.
  TextColumn get bbox => text().nullable()();

  /// Centroide, para que una fila de Airtable se pueda abrir en Google Maps de
  /// un clic.
  RealColumn get centroLat => real().nullable()();
  RealColumn get centroLon => real().nullable()();

  IntColumn get puntos => integer().withDefault(const Constant(0))();
  RealColumn get distanciaM => real().nullable()();

  /// Solo poligonos. La calcula el telefono con `core/geo.dart`; si la
  /// recalculara el backend con otra formula, el numero del papel y el de la
  /// base no coincidirian y ninguno de los dos seria creible.
  RealColumn get areaHa => real().nullable()();

  /// Promedio de la precision reportada por el GPS en los vertices. Es lo que
  /// decide si el trazado sirve para un lindero o solo para ubicarse.
  RealColumn get precisionMediaM => real().nullable()();

  DateTimeColumn get iniciadoEn => dateTime().nullable()();
  DateTimeColumn get terminadoEn => dateTime().nullable()();
  TextColumn get usuarioCodigo => text().nullable()();
}

class Waypoints extends Table with Sincronizable {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get proyectoCodigo => text()();
  TextColumn get trazadoCodigo => text().nullable()();
  TextColumn get nombre => text()();
  RealColumn get latitud => real()();
  RealColumn get longitud => real()();
  RealColumn get altitudM => real().nullable()();
  RealColumn get precisionM => real().nullable()();
  TextColumn get simbolo => text()();
  TextColumn get nota => text().nullable()();

  /// La hora que reporto el GPS, no la del telefono. Un telefono con la hora
  /// corrida deja waypoints que no se pueden cruzar con nada.
  DateTimeColumn get marcadoEn => dateTime()();
  TextColumn get usuarioCodigo => text().nullable()();
}

class Archivos extends Table with Sincronizable {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get proyectoCodigo => text()();
  TextColumn get trazadoCodigo => text().nullable()();
  TextColumn get waypointCodigo => text().nullable()();
  TextColumn get nombre => text()();
  TextColumn get tipo => text()();

  /// Donde esta en el telefono. Se conserva aunque ya este subido: el tecnico
  /// tiene que poder volver a compartir el KML sin red.
  TextColumn get rutaLocal => text()();

  /// Llave en S3. Null hasta que se sincroniza.
  TextColumn get llaveS3 => text().nullable()();

  RealColumn get tamanoMb => real().nullable()();
  TextColumn get usuarioCodigo => text().nullable()();
}

/// Log de cada intento de subida.
///
/// Existe para poder responder por que el trazado del martes no aparece, sin
/// adivinar: dice que se envio, que fallo y con que error.
class Sincronizaciones extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get codigo => text().unique()();
  DateTimeColumn get inicio => dateTime()();
  DateTimeColumn get fin => dateTime().nullable()();
  IntColumn get enviados => integer().withDefault(const Constant(0))();
  IntColumn get fallidos => integer().withDefault(const Constant(0))();
  TextColumn get estado => text()();
  TextColumn get detalle => text().nullable()();
}
