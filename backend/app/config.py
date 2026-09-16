from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Todo lo que el backend necesita saber y la app nunca puede ver.

    La regla que ordena este archivo: ninguna de estas cadenas puede terminar
    dentro del APK. El telefono conoce la URL del backend y su propia
    APP_API_KEY, y nada mas.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_api_key: str = ""

    # --- Airtable --------------------------------------------------------
    airtable_token: str = ""
    airtable_base_id: str = ""
    airtable_tabla_usuarios: str = "Usuarios"
    airtable_tabla_dispositivos: str = "Dispositivos"
    airtable_tabla_proyectos: str = "Proyectos"
    airtable_tabla_mapas: str = "Mapas"
    airtable_tabla_trazados: str = "Trazados"
    airtable_tabla_waypoints: str = "Waypoints"
    airtable_tabla_archivos: str = "Archivos"
    airtable_tabla_sincronizaciones: str = "Sincronizaciones"

    # --- Login -----------------------------------------------------------
    # Otra base y otro PAT, de solo lectura: ver .env.example.
    nomina_token: str = ""
    nomina_base_id: str = ""
    nomina_tabla: str = "Personal"

    # Hasta que orden jerarquico se considera Coordinador en ESTA app. En
    # nomina 1 = Super Admin y el numero sube al bajar el privilegio.
    nomina_orden_coordinador: int = 2

    # Cuantos dias puede el telefono validar la contrasena sin haber hablado
    # con el backend.
    dias_max_offline: int = 30

    # --- AWS S3 ----------------------------------------------------------
    aws_access_key_id: str = ""
    aws_secret_access_key: str = ""

    # Region real, no "auto": eso era de Cloudflare R2. S3 firma con la region
    # y una equivocada responde SignatureDoesNotMatch, que no dice que el
    # problema sea la region.
    aws_region: str = "us-east-1"
    s3_bucket: str = "sirius-geomaps"

    # CloudFront, si lo hay. Vacio = todo sale por URL prefirmada, que es lo
    # correcto para un bucket privado.
    s3_cloudfront_url: str = ""

    # Lectura larga porque bajar 400 MB de MBTiles sobre red rural tarda: si la
    # URL vence a mitad, la descarga reanudable reintenta contra una URL
    # muerta y el error que ve el usuario no dice nada util.
    s3_ttl_lectura: int = 86400
    s3_ttl_escritura: int = 3600


@lru_cache
def get_settings() -> Settings:
    return Settings()
