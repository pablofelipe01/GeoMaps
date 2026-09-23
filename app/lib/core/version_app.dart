/// Que version del APK esta vigente, y si la de este telefono todavia sirve.
///
/// La app se reparte como APK directo, sin Play Store: nadie empuja las
/// actualizaciones. La app le pregunta al backend (`GET /v1/version`), guarda
/// la respuesta, y con esa copia decide sola aunque no vuelva a tener senal.
///
/// La regla es la misma que aplica el backend en `services/version_app.py`, y
/// tiene que seguir siendolo: si la app cree que puede trabajar y el backend
/// no, la persona trabaja una semana y despues la sincronizacion le rebota.
///
/// | Version del telefono | Estado |
/// |---|---|
/// | `>= versionCode` | al dia |
/// | `< minima` | bloqueada, sin plazo |
/// | `< versionCode`, antes de `bloqueaEn` | desactualizada: aviso y sigue |
/// | `< versionCode`, desde `bloqueaEn` | bloqueada |
///
/// `bloqueaEn` es la fecha de publicacion mas los dias de gracia (10), y la
/// calcula el backend.
library;

enum EstadoVersion { alDia, desactualizada, bloqueada }

/// La version que corre en este telefono. Sale de `package_info_plus`, que la
/// lee del APK: es el `version:` del pubspec, `nombre+code`.
class VersionLocal {
  const VersionLocal({required this.code, required this.nombre});

  final int code;
  final String nombre;
}

/// La version vigente segun el ultimo manifiesto que se vio con red.
class VersionPublicada {
  const VersionPublicada({
    required this.versionCode,
    required this.versionNombre,
    required this.minima,
    required this.bloqueaEn,
    this.notas = '',
    this.tamanoBytes = 0,
    this.sha256,
    this.apkUrl,
  });

  factory VersionPublicada.deJson(Map<String, dynamic> j) => VersionPublicada(
    versionCode: j['version_code'] as int,
    versionNombre: j['version_nombre'] as String? ?? '',
    minima: j['minima'] as int? ?? 0,
    bloqueaEn: DateTime.parse(j['bloquea_en'] as String),
    notas: j['notas'] as String? ?? '',
    tamanoBytes: j['tamano_bytes'] as int? ?? 0,
    sha256: j['sha256'] as String?,
    apkUrl: j['apk_url'] as String?,
  );

  final int versionCode;
  final String versionNombre;
  final int minima;
  final DateTime bloqueaEn;
  final String notas;
  final int tamanoBytes;
  final String? sha256;

  /// Prefirmada, vence en un dia. Por eso antes de descargar se vuelve a
  /// consultar el backend en vez de usar la guardada.
  final String? apkUrl;

  Map<String, dynamic> aJson() => {
    'version_code': versionCode,
    'version_nombre': versionNombre,
    'minima': minima,
    'bloquea_en': bloqueaEn.toIso8601String(),
    'notas': notas,
    'tamano_bytes': tamanoBytes,
    'sha256': sha256,
    'apk_url': apkUrl,
  };

  /// La regla entera. Copia de `evaluar` en el backend.
  EstadoVersion evaluar(int local, DateTime ahora) {
    if (local >= versionCode) return EstadoVersion.alDia;
    if (local < minima || !ahora.isBefore(bloqueaEn)) {
      return EstadoVersion.bloqueada;
    }
    return EstadoVersion.desactualizada;
  }

  /// Dias que quedan antes del bloqueo, redondeando para arriba: con 3 horas
  /// por delante, "0 dias" haria creer que ya esta bloqueada.
  int diasParaBloqueo(DateTime ahora) {
    final falta = bloqueaEn.difference(ahora);
    if (falta.isNegative) return 0;
    return (falta.inMinutes / (60 * 24)).ceil();
  }

  /// "52 MB", para que la persona decida si lo baja con datos moviles.
  String get tamanoLegible {
    if (tamanoBytes <= 0) return '';
    return '${(tamanoBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

/// La hora contra la que se evalua.
///
/// Es la mayor entre el reloj del telefono y la ultima hora confiable que se
/// vio (la del servidor, o la del propio telefono en un chequeo anterior).
/// Atrasar el reloj a mano no esquiva el bloqueo: la hora nunca va para atras.
DateTime horaEfectiva(DateTime reloj, DateTime? ultimaConfiable) {
  if (ultimaConfiable == null || reloj.isAfter(ultimaConfiable)) return reloj;
  return ultimaConfiable;
}
