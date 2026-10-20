import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/core/api_client.dart';
import 'package:geomaps/core/geo.dart';
import 'package:geomaps/data/db/app_database.dart';
import 'package:geomaps/data/trazados_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// La baja de cuenta: que el telefono se quede sin lo de la persona y que un
/// fallo del backend no se confunda con un "listo".
void main() {
  test('borra los trazados del telefono', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TrazadosRepository(db);
    await repo.guardarRuta(
      usuarioCodigo: 'u1',
      nombre: 'Acopio 12',
      linea: const [PuntoGeo(4.28, -72.89), PuntoGeo(4.29, -72.88)],
      metros: 100,
    );

    await db.borrarDatosDeCuenta();

    expect(await db.select(db.trazados).get(), isEmpty);
  });

  test('el backend responde 204 y no hay error', () async {
    late http.Request pedido;
    final api = ApiClient(
      cliente: MockClient((r) async {
        pedido = r;
        return http.Response('', 204);
      }),
    )..token = 'jwt';

    await api.eliminarCuenta();

    expect(pedido.method, 'DELETE');
    expect(pedido.url.path, '/v1/cuenta');
    expect(pedido.headers['Authorization'], 'Bearer jwt');
  });

  test('si el backend no borro, se entera la pantalla', () async {
    final api = ApiClient(
      cliente: MockClient(
        (_) async => http.Response('{"detail": "Pedila a soporte."}', 409),
      ),
    );

    expect(
      api.eliminarCuenta,
      throwsA(
        isA<ApiError>().having((e) => e.mensaje, 'mensaje', 'Pedila a soporte.'),
      ),
    );
  });
}
