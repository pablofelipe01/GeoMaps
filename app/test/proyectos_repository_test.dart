// `hide isNull`: drift tambien exporta un isNull, que es un operador de SQL y
// no el matcher de las pruebas.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/data/db/app_database.dart';
import 'package:geomaps/data/proyectos_repository.dart';

/// Las pruebas del repositorio de proyectos corren contra un SQLite en memoria.
///
/// Lo que se verifica no es que drift funcione, sino las dos reglas que, si se
/// rompen, rompen datos de alguien: que un proyecto no se le muestre a otra
/// cuenta del mismo telefono, y que el resumen de MB cuente solo los mapas que
/// de verdad estan bajados.
void main() {
  late AppDatabase db;
  late ProyectosRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ProyectosRepository(db);
  });

  tearDown(() => db.close());

  test('crea un proyecto con UUID propio y sin sincronizar', () async {
    final creado = await repo.crear(
      duenoAuthUid: 'uid-1',
      nombre: '  El Roble  ',
    );

    expect(creado.codigo, isNotEmpty);
    expect(creado.nombre, 'El Roble', reason: 'el nombre se guarda sin bordes');
    expect(
      creado.sincronizado,
      isFalse,
      reason: 'nace pendiente: el telefono pudo haberlo creado sin senal',
    );
  });

  test(
    'los campos opcionales vacios quedan en null, no en cadena vacia',
    () async {
      final creado = await repo.crear(
        duenoAuthUid: 'uid-1',
        nombre: 'La Esperanza',
        cliente: '   ',
        municipio: '',
      );

      expect(creado.cliente, isNull);
      expect(creado.municipio, isNull);
    },
  );

  test('cada cuenta solo ve sus proyectos', () async {
    await repo.crear(duenoAuthUid: 'uid-1', nombre: 'De la cuenta 1');
    await repo.crear(duenoAuthUid: 'uid-2', nombre: 'De la cuenta 2');

    final deUno = await repo.observar('uid-1').first;

    expect(deUno, hasLength(1));
    expect(deUno.single.proyecto.nombre, 'De la cuenta 1');
  });

  test('archivar saca el proyecto de la lista sin borrarlo', () async {
    final p = await repo.crear(duenoAuthUid: 'uid-1', nombre: 'Temporal');

    await repo.archivar(p.codigo);
    expect(await repo.observar('uid-1').first, isEmpty);
    expect(
      await repo.observar('uid-1', soloActivos: false).first,
      hasLength(1),
    );

    await repo.archivar(p.codigo, activo: true);
    expect(await repo.observar('uid-1').first, hasLength(1));
  });

  test('el resumen cuenta solo los mapas bajados al telefono', () async {
    final p = await repo.crear(duenoAuthUid: 'uid-1', nombre: 'Con mapas');
    final ahora = DateTime.now();

    // Bajado: ocupa espacio y cuenta.
    await db
        .into(db.mapas)
        .insert(
          MapasCompanion.insert(
            codigo: 'mapa-bajado',
            creadoEn: ahora,
            proyectoCodigo: p.codigo,
            nombre: 'Topografia',
            formatoOrigen: 'geoTiff',
            estado: 'listo',
            rutaLocal: const Value('/datos/topografia.mbtiles'),
            tamanoMb: const Value(120.5),
          ),
        );

    // En el servidor pero sin bajar: no ocupa nada en el telefono.
    await db
        .into(db.mapas)
        .insert(
          MapasCompanion.insert(
            codigo: 'mapa-remoto',
            creadoEn: ahora,
            proyectoCodigo: p.codigo,
            nombre: 'Predial',
            formatoOrigen: 'geoPdf',
            estado: 'listo',
            tamanoMb: const Value(900),
          ),
        );

    final resumen = (await repo.observar('uid-1').first).single;

    expect(resumen.mapasDescargados, 1);
    expect(resumen.megasUsadas, 120.5);
  });

  test(
    'un proyecto sin mapas reporta cero y no desaparece de la lista',
    () async {
      await repo.crear(duenoAuthUid: 'uid-1', nombre: 'Recien creado');

      final resumen = (await repo.observar('uid-1').first).single;

      expect(resumen.mapasDescargados, 0);
      expect(resumen.megasUsadas, 0);
    },
  );

  test('contarActivos ignora los archivados y los de otras cuentas', () async {
    final uno = await repo.crear(duenoAuthUid: 'uid-1', nombre: 'Uno');
    await repo.crear(duenoAuthUid: 'uid-1', nombre: 'Dos');
    await repo.crear(duenoAuthUid: 'uid-2', nombre: 'De otro');

    expect(await repo.contarActivos('uid-1').first, 2);

    await repo.archivar(uno.codigo);
    expect(await repo.contarActivos('uid-1').first, 1);
  });
}
