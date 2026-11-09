#!/usr/bin/env python3
"""Deja una build de GeoMaps disponible en TestFlight, por la API de App Store Connect.

Se corre en el MAC PRO (ahi esta la llave .p8), despues de `./compilar_ios.sh N`
y cuando la build ya esta procesada (VALID). Ver docs/IOS.md.

    PY=~/Projects/mesh-portatil/tools/banco_meshcore/.venv/bin/python   # tiene PyJWT

    $PY enviar_testflight.py bundle      <- registra net.meshtrama.geomaps (ya hecho)
    $PY enviar_testflight.py estado      <- builds subidas y su estado
    $PY enviar_testflight.py interno N   <- grupo interno «Equipo_Sirius» con la build N
    $PY enviar_testflight.py externo N   <- grupo externo con enlace publico + Beta App Review

`externo` necesita una cuenta de prueba para el revisor de Apple (la app pide
login con correo y clave): GEOMAPS_DEMO_USUARIO y GEOMAPS_DEMO_CLAVE.

La primera revision de una VERSION tarda de horas a un dia; las builds siguientes de
la misma version suelen salir en minutos. No cambies la version sin razon.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

KEY_ID = "L87262Y77T"
ISSUER = "5b50c44f-6315-4ec3-9c22-e811470b8fbf"
# La llave vive fuera del repo y nunca se copia aca.
CLAVE = os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_L87262Y77T.p8")
BASE = "https://api.appstoreconnect.apple.com/v1/"

APP = os.environ.get("GEOMAPS_APP_ID", "6832715504")   # GeoMaps Sirius
BUNDLE = "net.meshtrama.geomaps"
NOMBRE = "GeoMaps Sirius"
APP_OFFAPP = "6804293198"     # Trama OffGrid Mesh: de ahi se copian los datos de contacto
GRUPO_INTERNO = "Equipo_Sirius"
GRUPO_EXTERNO = "Pruebas_Externas"

INFO_PRUEBA = {
    "locale": "es-MX",
    "description": (
        "GeoMaps muestra el plano georreferenciado de un predio sin señal: ubica al "
        "técnico de campo sobre el mapa con el GPS, traza la ruta por las vías internas "
        "de la plantación, marca puntos, graba recorridos y mide áreas. Los datos se "
        "guardan en el teléfono y se sincronizan cuando vuelve la red."),
    "feedbackEmail": "pablofelipe@me.com",
    "privacyPolicyUrl": "https://geo-maps-seven.vercel.app/privacidad",
}

NOTAS_REVISION = (
    "GeoMaps es una herramienta de campo para el equipo de Sirius. Se entra con la "
    "cuenta de prueba (correo y clave). Pide ubicación para mostrar la posición sobre el "
    "mapa; la ubicación en segundo plano solo se usa mientras se graba un viaje, que el "
    "usuario inicia y termina desde la app. La cámara lee el QR de vueltas pendientes "
    "(módulo Camiones).")


def _token():
    return jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
        open(CLAVE).read(), algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def _pedir(path, metodo="GET", cuerpo=None):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    r = urllib.request.Request(BASE + path, data=datos, method=metodo,
                               headers={"Authorization": f"Bearer {_token()}",
                                        "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r) as resp:
            crudo = resp.read()
            return json.loads(crudo) if crudo else {}, None
    except urllib.error.HTTPError as e:
        return None, f"{e.code}: {e.read().decode(errors='replace')[:400]}"


def app_id():
    """El Apple ID de la app; si se vacia APP, se busca por bundle."""
    if APP:
        return APP
    datos, err = _pedir(f"apps?filter[bundleId]={BUNDLE}")
    if err or not datos.get("data"):
        print(f"✗ no hay app con el bundle {BUNDLE} en App Store Connect: "
              f"{err or 'creala en la web (ver docs/IOS.md)'}")
        return None
    return datos["data"][0]["id"]


def registrar_bundle():
    ya, err = _pedir(f"bundleIds?filter[identifier]={BUNDLE}")
    if not err and ya.get("data"):
        print(f"✅ el bundle {BUNDLE} ya esta registrado")
        return 0
    _, err = _pedir("bundleIds", "POST", {"data": {"type": "bundleIds", "attributes": {
        "identifier": BUNDLE, "name": NOMBRE, "platform": "IOS"}}})
    print(f"✅ bundle {BUNDLE} registrado" if not err else f"✗ {err}")
    return 0 if not err else 1


def build_valida(app, numero):
    builds, err = _pedir(f"builds?filter[app]={app}&filter[version]={numero}&limit=1")
    if err or not builds.get("data"):
        print(f"✗ no encuentro la build {numero}: {err or 'sin resultados (sigue procesando?)'}")
        return None
    build = builds["data"][0]
    estado = build["attributes"]["processingState"]
    print(f"build {numero} · procesada: {estado}")
    if estado != "VALID":
        print("✗ todavia no esta VALID; espera unos minutos y vuelve a correrlo.")
        return None
    return build


def asegurar_info_prueba(app):
    datos, err = _pedir(f"apps/{app}/betaAppLocalizations")
    if err:
        print(f"✗ informacion de prueba: {err}")
        return False
    campos = {k: v for k, v in INFO_PRUEBA.items() if k != "locale"}
    existentes = datos.get("data", [])
    if existentes:
        _, err = _pedir(f"betaAppLocalizations/{existentes[0]['id']}", "PATCH",
                        {"data": {"type": "betaAppLocalizations", "id": existentes[0]["id"],
                                  "attributes": campos}})
    else:
        _, err = _pedir("betaAppLocalizations", "POST", {"data": {
            "type": "betaAppLocalizations", "attributes": INFO_PRUEBA,
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
    print("✅ informacion de prueba" if not err else f"✗ informacion de prueba: {err}")
    return not err


def asegurar_contacto_revision(app):
    usuario = os.environ.get("GEOMAPS_DEMO_USUARIO")
    clave = os.environ.get("GEOMAPS_DEMO_CLAVE")
    if not (usuario and clave):
        print("✗ faltan GEOMAPS_DEMO_USUARIO y GEOMAPS_DEMO_CLAVE: el revisor de Apple "
              "necesita una cuenta para pasar del login.")
        return False
    fuente, err = _pedir(f"apps/{APP_OFFAPP}/betaAppReviewDetail")
    if err:
        print(f"✗ no pude leer el contacto de la Off App: {err}")
        return False
    a = fuente["data"]["attributes"]
    destino, err = _pedir(f"apps/{app}/betaAppReviewDetail")
    if err:
        print(f"✗ contacto de revision: {err}")
        return False
    attrs = {k: a.get(k) for k in ("contactFirstName", "contactLastName",
                                    "contactPhone", "contactEmail")}
    attrs.update(demoAccountRequired=True, demoAccountName=usuario,
                 demoAccountPassword=clave, notes=NOTAS_REVISION)
    _, err = _pedir(f"betaAppReviewDetails/{destino['data']['id']}", "PATCH",
                    {"data": {"type": "betaAppReviewDetails", "id": destino["data"]["id"],
                              "attributes": attrs}})
    print(f"✅ contacto de revision ({attrs['contactFirstName']} {attrs['contactLastName']})"
          if not err else f"✗ contacto de revision: {err}")
    return not err


def asegurar_grupo(app, nombre, interno):
    grupos, err = _pedir(f"betaGroups?filter[app]={app}&limit=50")
    if err:
        print(f"✗ grupos: {err}")
        return None
    for g in grupos.get("data", []):
        if g["attributes"]["name"] == nombre:
            return g
    if interno:
        # Interno con acceso a todas las builds: cada build VALID nueva le llega
        # sola, sin revision de Apple. Los testers tienen que ser usuarios del
        # equipo en App Store Connect.
        attrs = {"name": nombre, "isInternalGroup": True, "hasAccessToAllBuilds": True}
    else:
        attrs = {"name": nombre, "publicLinkEnabled": True, "publicLinkLimit": 100,
                 "publicLinkLimitEnabled": True, "feedbackEnabled": True}
    g, err = _pedir("betaGroups", "POST", {"data": {
        "type": "betaGroups", "attributes": attrs,
        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
    if err:
        print(f"✗ no pude crear el grupo «{nombre}»: {err}")
        return None
    print(f"✅ grupo {'interno' if interno else 'externo con enlace publico'} «{nombre}» creado")
    return g["data"]


def asignar(grupo, build, nombre):
    _, err = _pedir(f"betaGroups/{grupo['id']}/relationships/builds", "POST",
                    {"data": [{"type": "builds", "id": build["id"]}]})
    if err and not err.startswith("409"):
        print(f"✗ no pude asignarla a «{nombre}»: {err}")
        return False
    print(f"✅ asignada a «{nombre}»")
    return True


def estado(app):
    builds, err = _pedir(f"builds?filter[app]={app}&sort=-uploadedDate&limit=10")
    if err:
        print(f"✗ {err}")
        return 1
    for b in builds.get("data", []):
        a = b["attributes"]
        print(f"build {a['version']:>4} · {a['processingState']:<10} · subida {a['uploadedDate']}")
    return 0


def interno(app, numero):
    build = build_valida(app, numero)
    if build is None or not asegurar_info_prueba(app):
        return 1
    grupo = asegurar_grupo(app, GRUPO_INTERNO, interno=True)
    if grupo is None:
        return 1
    if not grupo["attributes"].get("hasAccessToAllBuilds"):
        if not asignar(grupo, build, GRUPO_INTERNO):
            return 1
    print(f"✅ build {numero} disponible para «{GRUPO_INTERNO}». Agrega testers en App Store "
          "Connect → TestFlight → el grupo (tienen que ser usuarios del equipo).")
    return 0


def externo(app, numero):
    build = build_valida(app, numero)
    if build is None:
        return 1
    if not (asegurar_info_prueba(app) and asegurar_contacto_revision(app)):
        return 1
    grupo = asegurar_grupo(app, GRUPO_EXTERNO, interno=False)
    if grupo is None or not asignar(grupo, build, GRUPO_EXTERNO):
        return 1

    ya, _ = _pedir(f"builds/{build['id']}/betaAppReviewSubmission")
    if ya and ya.get("data"):
        print(f"✅ ya estaba en revision (estado: {ya['data']['attributes'].get('betaReviewState')})")
    else:
        _, err = _pedir("betaAppReviewSubmissions", "POST", {"data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
        if err and "ANOTHER_BUILD_IN_REVIEW" in err:
            # Apple revisa una build por version a la vez. No es un error nuestro.
            print("⏳ Apple todavia esta revisando una build anterior de esta version.\n"
                  "   Esta ya quedo en el grupo; vuelve a correr este mismo comando cuando\n"
                  "   llegue el correo de aprobacion.")
            return 0
        if err:
            print(f"✗ no pude enviarla a revision: {err}")
            return 1
        print("✅ enviada a Beta App Review (la primera vez: de horas a un dia)")

    g, _ = _pedir(f"betaGroups/{grupo['id']}")
    enlace = (g or {}).get("data", {}).get("attributes", {}).get("publicLink")
    if enlace:
        print(f"\n🔗 Enlace publico (sirve cuando Apple apruebe): {enlace}")
    return 0


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("bundle", "estado", "interno", "externo"):
        print(__doc__)
        return 2
    if sys.argv[1] == "bundle":
        return registrar_bundle()
    app = app_id()
    if app is None:
        return 1
    if sys.argv[1] == "estado":
        return estado(app)
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    return (interno if sys.argv[1] == "interno" else externo)(app, sys.argv[2])


if __name__ == "__main__":
    sys.exit(main())
