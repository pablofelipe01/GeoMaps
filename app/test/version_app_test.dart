import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/core/version_app.dart';

/// La misma tabla que `backend/tests/test_version_app.py`. Si una cambia y la
/// otra no, la app deja trabajar y el backend rechaza la sincronizacion.
void main() {
  final publicada = DateTime.utc(2026, 9, 1, 12);
  final vigente = VersionPublicada(
    versionCode: 3,
    versionNombre: '0.3.0',
    minima: 1,
    bloqueaEn: publicada.add(const Duration(days: 10)),
    tamanoBytes: 52 * 1024 * 1024,
  );

  group('evaluar', () {
    test('la vigente o una mas nueva estan al dia', () {
      final tarde = publicada.add(const Duration(days: 30));
      expect(vigente.evaluar(3, tarde), EstadoVersion.alDia);
      expect(vigente.evaluar(4, tarde), EstadoVersion.alDia);
    });

    test('dentro de los diez dias solo avisa', () {
      final casi = publicada.add(const Duration(days: 9, hours: 23));
      expect(vigente.evaluar(2, casi), EstadoVersion.desactualizada);
    });

    test('a los diez dias bloquea', () {
      final plazo = publicada.add(const Duration(days: 10));
      expect(vigente.evaluar(2, plazo), EstadoVersion.bloqueada);
    });

    test('por debajo de la minima bloquea sin esperar', () {
      expect(vigente.evaluar(0, publicada), EstadoVersion.bloqueada);
    });
  });

  test('los dias que quedan se redondean para arriba', () {
    final ahora = publicada.add(const Duration(days: 9, hours: 21));
    expect(vigente.diasParaBloqueo(ahora), 1);
    expect(vigente.diasParaBloqueo(publicada), 10);
    expect(vigente.diasParaBloqueo(publicada.add(const Duration(days: 11))), 0);
  });

  test('atrasar el reloj no esquiva el bloqueo', () {
    final servidor = publicada.add(const Duration(days: 12));
    final relojAtrasado = publicada;
    final ahora = horaEfectiva(relojAtrasado, servidor);
    expect(vigente.evaluar(2, ahora), EstadoVersion.bloqueada);
  });

  test('el manifiesto guardado se lee igual que se escribio', () {
    final copia = VersionPublicada.deJson(vigente.aJson());
    expect(copia.versionCode, 3);
    expect(copia.bloqueaEn, vigente.bloqueaEn);
    expect(copia.tamanoLegible, '52 MB');
  });
}
