"""Identidad: correo con clave o cuenta de Google, usuarios en Airtable.

GeoMaps no es una app interna de Sirius, asi que la identidad no puede salir de
la nomina: cualquiera crea la suya. No hay proveedor de identidad de por medio —
este backend verifica la credencial y guarda la persona en Airtable, que es la
unica plataforma que el equipo opera.

## Dos puertas, un solo usuario

| Proveedor | Credencial | `Auth UID` |
|---|---|---|
| `Google`  | ID token firmado por Google | el `sub` que trae el token |
| `Correo`  | correo + clave | `pwd_<uuid4>`, generado al registrarse |

Las dos terminan en el mismo lugar: una fila en `Usuarios` y un JWT propio de 30
dias. De ahi para adelante el resto del backend no sabe ni le importa por cual
puerta entro la persona.

**Una cuenta no puede tener las dos.** El `Correo` es unico en la tabla y el
`Proveedor` dice cual manda. Si alguien se registro con Google e intenta entrar
con clave (o al reves), la respuesta dice explicitamente por cual puerta le toca
entrar, en vez de "credenciales invalidas" — que es cierto y no sirve para nada.

## Que cuesta tener contrasenas

Antes no habia ninguna, y eso ahorraba tres flujos enteros donde los agujeros de
autenticacion se cuelan: recuperacion de clave, verificacion de correo y freno
de fuerza bruta. Ahora hay contrasenas, asi que hay que pagarlos:

- **Fuerza bruta**: pagado. `MAX_INTENTOS` fallos seguidos bloquean la cuenta
  `MINUTOS_BLOQUEO` minutos. El contador vive en Airtable porque este backend
  corre en funciones serverless: un contador en memoria se reinicia entre
  invocaciones y no frena absolutamente nada.
- **Hash**: pagado. bcrypt con sal por usuario. La clave en claro no se guarda,
  no se registra en logs y no vuelve nunca en una respuesta.
- **Verificacion de correo**: NO hecho. Una cuenta nueva por clave nace con
  `Correo verificado` en falso. Nada depende todavia de ese campo, pero el dia
  que algo dependa (avisos por correo, recuperacion), tiene que hacerse primero.
- **Recuperacion de clave**: NO hecho. Hace falta poder mandar correo, y este
  backend no manda correo. Mientras tanto, quien pierde la clave se recupera a
  mano desde Airtable. Esta es la deuda mas grande de este archivo.

## Como fluye

**Con Google**

1. La app abre Google Sign-In y recibe un ID token (un JWT firmado por Google).
2. Lo manda a `POST /v1/sesion`.
3. Aca se verifica contra el JWKS publico de Google: firma, `iss`, `aud`, `exp`.
4. Del token salen `sub`, correo, nombre y foto.
5. Upsert en `Usuarios` por ese `sub`. Si no existia, se acaba de registrar.

**Con clave**

1. `POST /v1/registro` con nombre, correo y clave -> se crea la fila con el hash.
2. `POST /v1/sesion/clave` con correo y clave -> se compara contra el hash.

Las dos devuelven exactamente la misma respuesta: el JWT propio y los datos de
la persona. La app no tiene dos caminos despues del login, solo dos formularios
antes.

## Por que emitir un JWT propio y no reusar el de Google

Tres razones, y la tercera es la que importa en campo:

1. El de Google vence en una hora y renovarlo obliga a pasar por Google.
2. Verificar el nuestro no cuesta una llamada de red.
3. **Nosotros elegimos el plazo.** Con `JWT_TTL_DIAS` en 30, alguien entra con
   senal una vez y trabaja un mes en el monte sin volver a ver un login.

El JWT propio lleva dentro el `codigo usuario` y el `Auth UID`, asi que las
llamadas normales no tocan Airtable para saber quien llama. Airtable topa en 5
requests por segundo por base y ese techo lo comparte con la sincronizacion: si
cada request gastara una consulta para identificar al usuario, un pico de gente
entrando dejaria sin cupo a los telefonos que estan subiendo el trabajo del dia.
"""

from __future__ import annotations

import re
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import bcrypt
import httpx
import jwt
from fastapi import Header, HTTPException
from jwt import PyJWKClient

from ..config import Settings, get_settings

# Los dos emisores que Google usa en sus ID tokens. Acepta las dos formas: la
# version sin esquema se emitio durante anos y todavia aparece.
EMISORES_GOOGLE = ("https://accounts.google.com", "accounts.google.com")

JWKS_GOOGLE = "https://www.googleapis.com/oauth2/v3/certs"

# El cliente de JWKS cachea las claves y solo vuelve a Google cuando aparece un
# `kid` que no conoce. Es global a proposito: uno por proceso, no uno por login.
_jwks = PyJWKClient(JWKS_GOOGLE, cache_keys=True)

# --- Reglas de la clave ---------------------------------------------------
# 8 es el minimo y no un capricho: mas corto que eso se rompe offline con una
# GPU en minutos, por mas que el hash sea bcrypt.
LARGO_MIN_CLAVE = 8

# bcrypt ignora todo lo que pase de 72 **bytes** — no caracteres. Una clave de
# 80 caracteres y otra que solo comparte los primeros 72 abren la misma cuenta,
# en silencio. Se rechaza antes de hashear en vez de truncar callados.
LARGO_MAX_CLAVE_BYTES = 72

# Fuerza bruta. Con 8 intentos cada 15 minutos, probar las mil claves mas
# comunes tarda mas de un dia; sin esto tarda un minuto.
MAX_INTENTOS = 8
MINUTOS_BLOQUEO = 15

# No valida direcciones de correo de verdad — eso no se puede hacer con una
# expresion regular y no vale la pena intentarlo. Solo descarta lo que
# claramente no es un correo antes de gastar una consulta a Airtable.
_CORREO = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

# Hash descartable con el que se compara cuando el correo no existe. Ver
# `verificar_clave`: sin esto, un correo inexistente responde notoriamente mas
# rapido que uno real y eso sirve para averiguar quien tiene cuenta.
_HASH_SENUELO = bcrypt.hashpw(b"cuenta-que-no-existe", bcrypt.gensalt(rounds=12))


@dataclass(frozen=True)
class Identidad:
    """Quien es la persona, ya verificado. Nunca se construye a mano."""

    auth_uid: str
    correo: str
    nombre: str
    foto: str | None
    codigo_usuario: str | None = None
    rol: str = "Usuario"


def verificar_id_token_google(id_token: str, settings: Settings) -> Identidad:
    """Valida el ID token contra el JWKS de Google y devuelve quien es.

    Todo lo que sigue se valida, sin excepciones: firma, emisor, audiencia y
    expiracion. Decodificar sin verificar seria darle al atacante un formulario
    para que escriba el `sub` que quiera.
    """
    if not settings.google_client_id_web:
        raise HTTPException(
            status_code=500,
            detail="Falta GOOGLE_CLIENT_ID_WEB. Sin el no se puede validar el "
            "token de Google.",
        )

    try:
        clave = _jwks.get_signing_key_from_jwt(id_token)
        datos = jwt.decode(
            id_token,
            clave.key,
            algorithms=["RS256"],
            # La audiencia es el client id **Web**. Sin este chequeo, un token
            # legitimo emitido para otra app cualquiera abriria sesion aca.
            audience=settings.google_client_id_web,
            issuer=list(EMISORES_GOOGLE),
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=401,
            detail="El token de Google vencio. Volve a entrar.",
        ) from None
    except jwt.InvalidAudienceError:
        # Es el error mas comun del primer arranque y el mas confuso: el token
        # es valido pero fue emitido para otro client id. Casi siempre significa
        # que la app mando el de Android como serverClientId en vez del Web.
        raise HTTPException(
            status_code=401,
            detail="El token de Google no fue emitido para esta app. Revisa que "
            "GOOGLE_SERVER_CLIENT_ID de la app y GOOGLE_CLIENT_ID_WEB del "
            "backend sean el MISMO client id de tipo Web.",
        ) from None
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=401, detail=f"Token de Google invalido: {exc}"
        ) from exc

    correo = datos.get("email")
    if not correo:
        raise HTTPException(
            status_code=401,
            detail="El token de Google no trae correo. Falta el scope 'email'.",
        )

    return Identidad(
        auth_uid=datos["sub"],
        correo=correo,
        # Alguien con cuenta sin nombre configurado igual tiene que poder entrar.
        nombre=datos.get("name") or correo.split("@")[0],
        foto=datos.get("picture"),
    )


# --- Puerta de correo + clave --------------------------------------------


def normalizar_correo(correo: str) -> str:
    """Minusculas y sin espacios. **Todo** lo que toque correos pasa por aca.

    `Ana@Gmail.com` y `ana@gmail.com` son la misma casilla, y si el registro
    guarda una forma y el login busca la otra, la cuenta queda inaccesible sin
    que nada parezca roto. Normalizar en un solo lugar es lo que evita eso.
    """
    return correo.strip().lower()


def validar_correo(correo: str) -> str:
    """Normaliza y rechaza lo que claramente no es un correo."""
    limpio = normalizar_correo(correo)
    if not _CORREO.match(limpio):
        raise HTTPException(
            status_code=400, detail="Ese correo no parece valido."
        )
    return limpio


def validar_clave(clave: str) -> None:
    """Rechaza claves que no se pueden usar. No juzga cuan buenas son.

    No exige mayusculas ni simbolos a proposito: esas reglas empujan a la gente
    a `Password1!` y a escribirla en un papel. El largo minimo hace mas.
    """
    if len(clave) < LARGO_MIN_CLAVE:
        raise HTTPException(
            status_code=400,
            detail=f"La clave debe tener al menos {LARGO_MIN_CLAVE} caracteres.",
        )
    if len(clave.encode("utf-8")) > LARGO_MAX_CLAVE_BYTES:
        raise HTTPException(
            status_code=400,
            detail="La clave es demasiado larga (maximo 72 bytes). Las tildes y "
            "los emojis cuentan por varios.",
        )


def hash_clave(clave: str) -> str:
    """bcrypt con sal propia. Es lo unico que se guarda de una contrasena."""
    validar_clave(clave)
    return bcrypt.hashpw(clave.encode("utf-8"), bcrypt.gensalt(rounds=12)).decode()


def verificar_clave(clave: str, hash_guardado: str | None) -> bool:
    """Compara contra el hash. Tarda lo mismo exista o no exista la cuenta.

    Cuando no hay hash — porque el correo no esta registrado, o porque esa
    cuenta es de Google y nunca tuvo clave — igual se corre bcrypt contra un
    senuelo. Sin eso, un correo inexistente contesta en un milisegundo y uno
    real en trescientos, y esa diferencia se mide desde afuera: alcanza para
    sacar la lista de quien tiene cuenta en el sistema.
    """
    objetivo = (hash_guardado or "").encode("utf-8") or _HASH_SENUELO
    try:
        return bcrypt.checkpw(clave.encode("utf-8"), objetivo)
    except ValueError:
        # Hash corrupto o en un formato que bcrypt no reconoce — alguien edito
        # la celda a mano en Airtable. No abre la sesion, pero tampoco tumba el
        # endpoint con un 500.
        return False


def nuevo_auth_uid_correo() -> str:
    """El `Auth UID` de una cuenta con clave.

    Prefijo `pwd_` para que no pueda chocar nunca con un `sub` de Google, que
    es siempre una cadena de digitos. Tambien deja ver de que tipo es una
    cuenta con solo mirar la celda en Airtable.
    """
    return f"pwd_{uuid.uuid4()}"


def formula_por_correo(correo: str) -> str:
    """Busca una fila de `Usuarios` por correo, sin importar mayusculas.

    `LOWER()` del lado de Airtable porque filas viejas pueden tener el correo
    tal como lo escribio Google, con mayusculas.
    """
    seguro = normalizar_correo(correo).replace("'", "")
    return f"LOWER({{Correo}})='{seguro}'"


def revisar_bloqueo(campos: dict) -> None:
    """Frena la fuerza bruta. Se llama antes de comparar la clave.

    El contador vive en Airtable y no en memoria porque este backend corre en
    funciones serverless: cada invocacion puede ser un proceso nuevo, y un
    contador que se reinicia solo no frena nada.
    """
    intentos = campos.get("Intentos fallidos") or 0
    if intentos < MAX_INTENTOS:
        return

    ultimo = campos.get("Ultimo intento fallido")
    if not ultimo:
        return
    try:
        cuando = datetime.fromisoformat(str(ultimo).replace("Z", "+00:00"))
    except ValueError:
        return

    if cuando.tzinfo is None:
        cuando = cuando.replace(tzinfo=timezone.utc)
    libre = cuando + timedelta(minutes=MINUTOS_BLOQUEO)
    faltan = libre - datetime.now(timezone.utc)
    if faltan.total_seconds() > 0:
        minutos = max(1, int(faltan.total_seconds() // 60) + 1)
        raise HTTPException(
            status_code=429,
            detail=f"Demasiados intentos fallidos. Volve a probar en {minutos} "
            "minuto(s), o pedi ayuda para restablecer la clave.",
        )


def emitir_jwt(identidad: Identidad, settings: Settings) -> tuple[str, datetime]:
    """Firma nuestro JWT y dice cuando vence.

    Devuelve tambien la fecha porque la app la guarda: asi puede decir sin red
    cuantos dias de trabajo offline le quedan, en vez de descubrirlo con un 401
    en medio de un potrero.
    """
    if not settings.jwt_secret:
        raise HTTPException(
            status_code=500, detail="Falta JWT_SECRET en el backend."
        )

    vence = datetime.now(timezone.utc) + timedelta(days=settings.jwt_ttl_dias)
    token = jwt.encode(
        {
            "sub": identidad.auth_uid,
            "uid": identidad.codigo_usuario,
            "rol": identidad.rol,
            "correo": identidad.correo,
            "iat": int(time.time()),
            "exp": int(vence.timestamp()),
        },
        settings.jwt_secret,
        algorithm="HS256",
    )
    return token, vence


async def identidad_de_request(
    authorization: str | None = Header(default=None),
) -> Identidad:
    """Dependencia de FastAPI: quien esta llamando.

    Verifica NUESTRO jwt, no el de Google, y **no consulta Airtable**. Es lo que
    corre en cada endpoint.
    """
    settings = get_settings()
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Falta el token de sesion.")

    try:
        datos = jwt.decode(
            authorization[7:], settings.jwt_secret, algorithms=["HS256"]
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=401,
            detail="La sesion vencio. Busca senal y volve a entrar; el trabajo "
            "guardado en el telefono no se pierde.",
        ) from None
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Sesion invalida.") from None

    return Identidad(
        auth_uid=datos["sub"],
        correo=datos.get("correo", ""),
        nombre="",
        foto=None,
        codigo_usuario=datos.get("uid"),
        rol=datos.get("rol", "Usuario"),
    )


def formula_del_duenno(auth_uid: str) -> str:
    """El filtro de aislamiento entre cuentas. **Todo listado pasa por aca.**

    Airtable no tiene seguridad por fila: el PAT ve la base entera. Lo unico que
    separa los predios de un usuario de los de otro es que este filtro se
    aplique en cada consulta. Un endpoint que se olvide le entrega a un
    desconocido los linderos de un predio ajeno.

    Vive en una sola funcion y no escrito a mano en cada servicio porque es una
    regla que no se sostiene con disciplina: se sostiene con que no haya otra
    forma de escribir la consulta.
    """
    # Las comillas se escapan porque el UID entra en una formula de Airtable.
    seguro = auth_uid.replace("'", "")
    return f"{{Dueno Auth UID}}='{seguro}'"


async def verificar_api_key(x_api_key: str | None = Header(default=None)) -> None:
    """Dice que quien llama es la app, no quien es la persona.

    Son preguntas distintas y hacen falta las dos: sin esta, cualquiera golpea
    el endpoint de sesion en un bucle; sin el JWT, no se sabe de quien es el
    trazado.
    """
    settings = get_settings()
    if not settings.app_api_key:
        return  # Sin configurar, en desarrollo, no bloquea.
    if x_api_key != settings.app_api_key:
        raise HTTPException(status_code=401, detail="X-API-Key invalida.")


async def cerrar_jwks() -> None:
    """Para el shutdown del server."""
    async with httpx.AsyncClient() as _:
        pass
