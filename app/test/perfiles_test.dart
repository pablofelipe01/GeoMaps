import 'package:flutter_test/flutter_test.dart';
import 'package:geomaps/state/sesion.dart';

/// Los perfiles: que una sesion guardada antes de que existieran siga
/// funcionando igual, y que sobrevivan a guardarse y leerse sin red.
void main() {
  Map<String, dynamic> json({Object? perfiles}) => {
    'auth_uid': '111',
    'codigo_usuario': 'u1',
    'nombre': 'Ana',
    'correo': 'ana@x.co',
    'rol': 'Usuario',
    'vence_en': '2026-11-13T00:00:00.000Z',
    'perfiles': ?perfiles,
  };

  test('una sesion vieja, sin perfiles, es de plantacion', () {
    final s = Sesion.deJson(json());
    expect(s.perfiles, {Perfil.plantacion});
  });

  test('ignora un perfil que este APK no conoce', () {
    final s = Sesion.deJson(json(perfiles: ['camiones', 'drones']));
    expect(s.perfiles, {Perfil.camiones});
    expect(s.tiene(Perfil.plantacion), isFalse);
  });

  test('sobrevive a guardarse y leerse', () {
    final s = Sesion.deJson(json(perfiles: ['plantacion', 'camiones']));
    final vuelta = Sesion.deJson(s.aJson());
    expect(vuelta.perfiles, {Perfil.plantacion, Perfil.camiones});
  });
}
