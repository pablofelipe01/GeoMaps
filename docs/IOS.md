# GeoMaps en iOS (TestFlight)

| Dato | Valor |
|---|---|
| Bundle ID | `net.meshtrama.geomaps` (registrado, id `8M7DK7BQ6M`) |
| App en App Store Connect | «GeoMaps Sirius», SKU `geomaps-ios`, idioma Español (México) |
| App Apple ID | `6832715504` |
| Equipo | `G4M5669P37` (cuenta de pago). **No** el Personal Team `GVNKN88482` |
| Firma | Automática en Xcode |
| iOS mínimo | 15.0 (pbxproj y Podfile) |
| API Key App Store Connect | Key ID `L87262Y77T`, Issuer `5b50c44f-6315-4ec3-9c22-e811470b8fbf`, rol App Manager |

La llave `.p8` vive en `~/.appstoreconnect/private_keys/` del **Mac Pro** y nunca
entra al repositorio.

## Flutter

GeoMaps pide Dart `^3.13`. El Flutter de Homebrew del Mac Pro es más viejo y lo
usan otros proyectos, así que GeoMaps compila con un SDK aparte en
`~/flutter-stable` (canal stable). `compilar_ios.sh` ya lo usa; para otro SDK,
`FLUTTER=/ruta/a/flutter ./compilar_ios.sh N`.

## Subir la siguiente build

En el Mac Pro, desde `app/`, con `dart_defines.json` presente (es el mismo del
APK y no se commitea):

1. Subir el número de build. **La versión de `pubspec.yaml` no se toca**: Apple
   aprueba la revisión externa por versión, y con la misma versión las builds
   nuevas salen en minutos. El número tiene que ser mayor que el último subido
   (`enviar_testflight.py estado` lo muestra).

   ```
   cd ~/Projects/GeoMaps/app && ./compilar_ios.sh 10
   ```

   Compila con `flutter build ipa` y sube con `xcrun altool --upload-app`
   (audiencia App Store). **Nunca** subir desde el Organizer con «TestFlight
   Internal Only»: esa build después no se puede mandar a testers externos.

2. Esperar a que quede `VALID` (10-20 min):

   ```
   ~/Projects/mesh-portatil/tools/banco_meshcore/.venv/bin/python ~/Projects/GeoMaps/app/enviar_testflight.py estado
   ```

3. Grupo interno «Equipo_Sirius», sin revisión de Apple. Tiene acceso a todas
   las builds, así que cada build `VALID` nueva le llega sola:

   ```
   ~/Projects/mesh-portatil/tools/banco_meshcore/.venv/bin/python ~/Projects/GeoMaps/app/enviar_testflight.py interno 10
   ```

4. Grupo externo «Pruebas_Externas» con enlace público, y Beta App Review. El
   revisor necesita una cuenta de correo y clave:

   ```
   GEOMAPS_DEMO_USUARIO=correo@ejemplo.com GEOMAPS_DEMO_CLAVE='...' ~/Projects/mesh-portatil/tools/banco_meshcore/.venv/bin/python ~/Projects/GeoMaps/app/enviar_testflight.py externo 10
   ```

## Qué cambia en iOS respecto de Android

- **Sin Google Sign-In.** No hay client OAuth de tipo iOS todavía; sin él, el
  plugin cierra la app al tocar el botón. En iPhone se entra con correo y clave.
  Para activarlo: crear el client iOS en Google Cloud con el bundle de arriba,
  poner `GIDClientID` y su URL scheme invertido en `ios/Runner/Info.plist`,
  aceptar ese client id como audiencia en el backend, y quitar los
  `Platform.isIOS` de `login_page.dart` y `sesion.dart`.
- **Sin actualizador de APK.** En iOS `_versionLocal()` devuelve null: no se
  manda `X-App-Version` (el backend no le responde 426 a un iPhone por la regla
  de versiones de Android) y la pantalla de actualización no aparece. Las
  versiones llegan por TestFlight / App Store.
- **Ubicación en segundo plano** con `AppleSettings` y
  `UIBackgroundModes=location`, solo mientras se graba un viaje. iOS muestra la
  barra azul.
- **Info.plist:** `ITSAppUsesNonExemptEncryption=false` y descripciones de
  ubicación (cuando se usa y siempre), cámara (QR de camiones) y Fotos (guardar
  lo exportado).
- **Iconos** generados por `flutter_launcher_icons` sin canal alfa. App Store
  rechaza el icono con alfa.
