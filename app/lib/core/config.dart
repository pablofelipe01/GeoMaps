/// Configuracion de compilacion.
///
/// Todo entra por `--dart-define`, nunca por un archivo commiteado: un APK
/// anda en el bolsillo de alguien y cualquier cadena adentro es publica. Por
/// eso aca no hay ni un token de Airtable ni una llave del bucket, solo la URL
/// del backend y la llave propia de la app.
class Config {
  /// URL del backend. En el emulador de Android el localhost de la maquina es
  /// 10.0.2.2, no 127.0.0.1.
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Viaja en el header X-API-Key. No identifica al usuario, solo dice que
  /// quien llama es esta app.
  static const apiKey = String.fromEnvironment('API_KEY');

  /// Cuantos dias puede el telefono validar la contrasena contra el hash local
  /// sin haber hablado con el backend. Pasado el plazo exige un login con red,
  /// que es lo unico que ve si la persona sigue activa en nomina.
  static const diasMaxOffline = 30;
}
