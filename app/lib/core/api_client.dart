import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Cliente HTTP contra el backend.
///
/// Regla que ordena este archivo: **ningun metodo de aca puede ser necesario
/// para que la app funcione en campo.** Todos sirven para sincronizar,
/// descargar mapas o entrar por primera vez. Si uno falla, la pantalla que lo
/// llamo sigue andando con lo que tiene en la base local.
///
/// Toda llamada lleva estas cabeceras y no son lo mismo:
///
///   X-API-Key      -> quien llama es GeoMaps
///   Authorization  -> quien es la persona (nuestro JWT, 30 dias)
///   X-App-Version  -> que APK es (el versionCode). Si ya esta bloqueado, el
///                     backend responde 426 a todo menos a `/v1/version`
///
/// Las tres puertas de entrada — Google, registro con clave y login con clave —
/// devuelven el mismo cuerpo, y por eso comparten `_sesion`. Para el resto de
/// la app no existe la diferencia.
class ApiClient {
  ApiClient({http.Client? cliente, this.versionCode})
    : _http = cliente ?? http.Client();

  final http.Client _http;

  /// El versionCode de este APK. Null solo en pruebas.
  final int? versionCode;

  /// Se llama cuando el backend responde 426: esta version ya no sirve. Lo
  /// conecta `ActualizacionNotifier`, que vuelve a consultar y bloquea.
  void Function()? alVersionVencida;

  /// El JWT de la sesion activa. Lo pone `SesionState` al entrar.
  String? token;

  Uri _uri(String ruta) => Uri.parse('${Config.apiBase}$ruta');

  Map<String, String> _cabeceras({bool conToken = true}) => {
    'Content-Type': 'application/json',
    if (Config.apiKey.isNotEmpty) 'X-API-Key': Config.apiKey,
    if (conToken && token != null) 'Authorization': 'Bearer $token',
    if (versionCode != null) 'X-App-Version': '$versionCode',
  };

  /// Arma el error de una respuesta fallida, y avisa si fue por version.
  ApiError _fallo(http.Response r) {
    if (r.statusCode == 426) alVersionVencida?.call();
    return ApiError.deRespuesta(r);
  }

  /// Cambia el idToken de Google por nuestro JWT. Es tambien el registro: si el
  /// `sub` no existia en Airtable, el backend crea la fila.
  Future<Map<String, dynamic>> entrar(String idTokenGoogle) =>
      _sesion('/v1/sesion', {'id_token': idTokenGoogle});

  /// Entra a una cuenta que ya existe, con correo y clave.
  Future<Map<String, dynamic>> entrarConClave(String correo, String clave) =>
      _sesion('/v1/sesion/clave', {'correo': correo, 'clave': clave});

  /// Crea una cuenta con correo y clave. Devuelve sesion abierta, no un "ya te
  /// podes loguear": el registro pasa con red y mandar a la persona a un
  /// segundo formulario desperdicia el unico rato con senal que va a tener.
  Future<Map<String, dynamic>> registrar({
    required String nombre,
    required String correo,
    required String clave,
  }) => _sesion('/v1/registro', {
    'nombre': nombre,
    'correo': correo,
    'clave': clave,
  });

  /// Las tres puertas devuelven el mismo cuerpo, asi que comparten la llamada.
  ///
  /// El registro responde 201 y los logins 200. Se aceptan los dos para no
  /// tener una rama por endpoint que diga lo mismo.
  Future<Map<String, dynamic>> _sesion(
    String ruta,
    Map<String, String> cuerpo,
  ) async {
    final r = await _http
        .post(
          _uri(ruta),
          headers: _cabeceras(conToken: false),
          body: jsonEncode(cuerpo),
        )
        // En red rural un timeout largo no ayuda: si a los 20 s no contesto, no
        // va a contestar, y la persona necesita el mensaje para decidir si se
        // mueve a buscar senal.
        .timeout(const Duration(seconds: 20));

    if (r.statusCode != 200 && r.statusCode != 201) {
      throw _fallo(r);
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// Comprueba que la sesion siga valiendo. No consulta Airtable del otro lado.
  Future<Map<String, dynamic>> yo() async {
    final r = await _http
        .get(_uri('/v1/yo'), headers: _cabeceras())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw _fallo(r);
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// La version vigente del APK y la URL para bajarlo. No pide sesion: una app
  /// bloqueada o con la sesion vencida igual tiene que poder actualizarse.
  ///
  /// Devuelve el cuerpo crudo; `publicada` en falso significa que todavia no
  /// se publico ninguna version por el canal de actualizaciones.
  Future<Map<String, dynamic>> version() async {
    final r = await _http
        .get(_uri('/v1/version'), headers: _cabeceras(conToken: false))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw ApiError.deRespuesta(r);
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // TODO: GET  /v1/proyectos            -> espejo del directorio
  // TODO: GET  /v1/mapas?proyecto=      -> fichas de mapas listos
  // TODO: GET  /v1/mapas/{id}/descarga  -> URL prefirmada del MBTiles
  // TODO: POST /v1/sync                 -> upsert por UUID de lo pendiente
  // TODO: POST /v1/archivos             -> sube KML/GPX/PDF/foto a S3
}

/// Un error del backend con el texto que el backend quiso dar.
///
/// El `detail` de FastAPI se muestra tal cual porque esta escrito para que lo
/// lea alguien parado en un lote, no para un log. Un "Error 401" generico ahi no
/// sirve de nada.
class ApiError implements Exception {
  ApiError(this.codigo, this.mensaje);

  factory ApiError.deRespuesta(http.Response r) {
    String mensaje;
    try {
      final cuerpo = jsonDecode(utf8.decode(r.bodyBytes));
      mensaje = (cuerpo is Map && cuerpo['detail'] != null)
          ? cuerpo['detail'].toString()
          : 'El servidor respondio ${r.statusCode}.';
    } catch (_) {
      mensaje = 'El servidor respondio ${r.statusCode}.';
    }
    return ApiError(r.statusCode, mensaje);
  }

  final int codigo;
  final String mensaje;

  /// La sesion vencio o no vale. Es el unico caso que obliga a volver al login.
  bool get sesionInvalida => codigo == 401;

  /// Esta version del APK ya no se acepta. La app muestra la pantalla de
  /// actualizar; no es algo que se arregle reintentando.
  bool get requiereActualizar => codigo == 426;

  @override
  String toString() => mensaje;
}
