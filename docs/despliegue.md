# Despliegue

## Backend en Vercel

La carpeta `backend/` se despliega sola. `pyproject.toml` usa la sintaxis
correcta de Vercel: `[tool.vercel] entrypoint = "app.main:app"`. Esa forma
le dice al runtime que importe el paquete `app.main` y el objeto `app` de
FastAPI; sin ella, Vercel busca un modulo plano y los imports relativos
(`from .config import ...`) se rompen fuera del paquete.

```bash
cd backend
vercel --prod
```

Las variables del `.env.example` se cargan en el panel de Vercel, no en un
archivo. Las que no pueden faltar para que algo funcione:

| Variable | Sin ella |
|---|---|
| `APP_API_KEY` | Todos los endpoints responden 401 |
| `AIRTABLE_TOKEN` + `AIRTABLE_BASE_ID` | La sincronizacion falla; la app sigue trabajando offline |
| `AWS_*` + `S3_BUCKET` | No se pueden subir archivos ni descargar mapas |
| `GOOGLE_CLIENT_ID_WEB` + `JWT_SECRET` | Nadie puede entrar ni registrarse |

## Google Sign-In: lo unico que hay que crear fuera de Airtable y AWS

No es una plataforma nueva que haya que contratar ni pagar: es un proyecto en
**Google Cloud Console**, gratis, y solo se usa para emitir client id de OAuth.
Se hace una vez.

1. Crear un proyecto en <https://console.cloud.google.com>.
2. Configurar la **pantalla de consentimiento** de OAuth. Como el registro es
   abierto, va en modo **External** y en `Publicada`. En modo `Testing` solo
   entran hasta 100 correos cargados a mano, que es justo lo contrario de lo que
   se busca.
3. Crear **dos** client id en Credenciales:

   | Tipo | Para que | Donde va |
   |---|---|---|
   | **Web** | Es el `aud` del ID token. La app lo manda como `serverClientId` | `GOOGLE_CLIENT_ID_WEB` en Vercel, y `GOOGLE_SERVER_CLIENT_ID` en el build del APK |
   | **Android** | Liga la firma del APK a la cuenta | `GOOGLE_CLIENT_ID_ANDROID`. Pide el nombre del paquete y la huella **SHA-1** |

**Los dos hacen falta, y es donde se pierde media tarde.** Sin el de tipo Web,
`google_sign_in` en Android abre sesion pero **no devuelve `idToken`**, y el
backend se queda sin nada que verificar: la app parece funcionar hasta que
falla la llamada a `/v1/sesion`. Sin el de Android, el login muere con
`ApiException: 10`, que no dice nada.

### Las huellas SHA-1 son dos, no una

```bash
# Debug: la que usa `flutter run` en la maquina de cada quien
keytool -list -v -alias androiddebugkey \
  -keystore ~/.android/debug.keystore -storepass android

# Release: la del keystore con el que se firma el APK que se distribuye
keytool -list -v -alias <alias> -keystore <ruta>.jks
```

Las dos se registran en el client id de Android. El error clasico es cargar solo
la de debug: el login anda perfecto en desarrollo y falla en el APK que recibe
la gente.

## El worker de conversion

**No va en Vercel.** GDAL necesita binarios del sistema y convertir un raster
grande son minutos de CPU y varios GB de temporales: no cabe en una funcion
serverless.

Opciones, de menor a mayor esfuerzo:

1. **A mano**, con los comandos de `tools/README.md`. Es lo razonable mientras
   sean unos pocos mapas al mes, que es el caso hoy.
2. Un contenedor con `osgeo/gdal` en cualquier VM, leyendo una cola.

Mientras sea (1), el endpoint `POST /v1/mapas` guarda el original en el bucket
y deja el registro en `Procesando`. Alguien corre GDAL, sube el MBTiles y
marca `Listo`. La app no ve diferencia: para ella un mapa esta listo o no.

## APK

```bash
cd app
flutter build apk --release \
  --dart-define=API_BASE=https://geomaps-api.vercel.app \
  --dart-define=API_KEY=...
```

Las llaves entran por `--dart-define`, nunca por un archivo commiteado: un APK
anda en el bolsillo de alguien y cualquier cadena adentro es publica.

Para distribuir sin Play Store, que es lo que corresponde a una app interna, el
APK se sube a un enlace privado. Los telefonos necesitan permitir instalacion
de origenes desconocidos una sola vez.

### Permisos que Android va a pedir

| Permiso | Para que | Cuando se pide |
|---|---|---|
| Ubicacion precisa | Todo | Al abrir el mapa |
| Ubicacion en segundo plano | Grabar un trazado con la pantalla apagada | Solo al iniciar el primer trazado, explicando por que |
| Camara | Fotos de waypoints | Al tomar la primera |
| Almacenamiento | Importar un MBTiles del telefono | Al importar |

El de segundo plano se pide aparte y tarde a proposito: Android muestra un
dialogo severo, y pedirlo en el primer arranque sin contexto hace que la gente
lo niegue y despues no entienda por que el trazado se corta.

## Base de Airtable

Se crea a mano siguiendo `docs/airtable-schema.md`, y despues:

```bash
cd backend
python scripts/verificar_esquema.py
```

Ese script compara lo que existe en Airtable contra el documento. Vale la pena
correrlo tambien despues de cualquier cambio en la interfaz de Airtable:
alguien renombra un campo, el upsert empieza a fallar en silencio con typecast,
y el trabajo de campo de esa semana no aparece.
