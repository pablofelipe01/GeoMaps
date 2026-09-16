# Despliegue

## Backend en Vercel

La carpeta `backend/` se despliega sola. `pyproject.toml` ya trae el
`[tool.vercel] entrypoint = "app/main.py"`: sin el, Vercel busca `main.py` en
la raiz, lo carga suelto, y los imports relativos (`from .config import ...`)
revientan al importarse fuera del paquete.

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
| `NOMINA_TOKEN` + `NOMINA_BASE_ID` | Nadie puede hacer el primer login |

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
