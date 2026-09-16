import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// La base local. El codigo generado sale de:
///
/// ```bash
/// dart run build_runner build --delete-conflicting-outputs
/// ```
///
/// `app_database.g.dart` no se versiona: se regenera, y tenerlo en git solo
/// produce conflictos de merge en codigo que nadie edita a mano.
@DriftDatabase(
  tables: [
    Usuarios,
    Proyectos,
    Mapas,
    Trazados,
    Waypoints,
    Archivos,
    Sincronizaciones,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  // TODO: MigrationStrategy. Cuando llegue la v2, migrar en serio: un
  // `deleteEverything` en una app offline borra el trabajo de campo de alguien
  // que todavia no sincronizo.
}
