"""Compila el .aab para Play Store y revisa que se pueda subir.

    backend/.venv/Scripts/python tools/compilar_play.py

No sube nada: el bundle se arrastra a mano en Play Console. Lo que hace es
evitar los tres errores que no se ven hasta que alguien instala la app:

- **Compilar sin `dart_defines.json`.** El bundle sale sin API_KEY ni client id
  de Google: instala bien y despues no puede ni iniciar sesion.
- **Firmar con la llave de debug.** Play lo rechaza, y aunque no lo hiciera, no
  es la llave registrada.
- **Colar permisos que Play objeta.** REQUEST_INSTALL_PACKAGES (la app se
  actualizaria por fuera de la tienda) o RECORD_AUDIO (microfono, que la app no
  usa). Los quita `src/play/AndroidManifest.xml`; si un plugin nuevo los vuelve
  a meter, se detecta aca y no en la revision de Google.

Con `--sin-build` revisa el bundle ya compilado.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

from publicar_apk import APP, fallar, version_del_pubspec

AAB = APP / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"

PROHIBIDOS = {
    "android.permission.REQUEST_INSTALL_PACKAGES": (
        "la app podria instalarse versiones por fuera de Play"
    ),
    "android.permission.RECORD_AUDIO": "pide microfono y la app no lo usa",
}


def compilar() -> None:
    defines = APP / "dart_defines.json"
    if not defines.exists():
        fallar("Falta app/dart_defines.json (API_KEY, GOOGLE_SERVER_CLIENT_ID).")
    flutter = shutil.which("flutter") or shutil.which("flutter.bat")
    if not flutter:
        fallar("No se encontro `flutter` en el PATH.")
    print("Compilando el bundle de release para Play...")
    r = subprocess.run(
        [
            flutter,
            "build",
            "appbundle",
            "--release",
            f"--dart-define-from-file={defines.name}",
        ],
        cwd=APP,
    )
    if r.returncode != 0:
        fallar("Fallo la compilacion.")


def permisos(aab: Path) -> set[str]:
    """Los permisos del manifiesto del bundle.

    En un .aab el manifiesto va en formato protobuf, no en XML binario, pero
    los nombres quedan como texto plano. Se lee solo el valor que sigue a cada
    `uses-permission` (a unos 50 bytes, despues del namespace): buscar
    `android.permission.` en todo el archivo tambien trae el atributo
    `android:permission` de servicios y receivers, que no es un permiso que la
    app pida.
    """
    with zipfile.ZipFile(aab) as z:
        crudo = z.read("base/manifest/AndroidManifest.xml")
    encontrados = set()
    for elemento in re.finditer(rb"uses-permission", crudo):
        tramo = crudo[elemento.end() : elemento.end() + 120]
        m = re.search(rb"android\.permission\.[A-Z_]+", tramo)
        if m:
            encontrados.add(m.group().decode())
    return encontrados


def firma(aab: Path) -> dict[str, str]:
    keytool = shutil.which("keytool")
    if not keytool:
        fallar("No se encontro `keytool` (viene con el JDK).")
    r = subprocess.run(
        # En ingles para poder leerlo: keytool traduce las etiquetas.
        [keytool, "-J-Duser.language=en", "-printcert", "-jarfile", str(aab)],
        capture_output=True,
        text=True,
    )
    salida = r.stdout
    dueno = re.search(r"Owner:\s*(.+)", salida)
    sha1 = re.search(r"SHA1:\s*([0-9A-F:]+)", salida)
    if r.returncode != 0 or not dueno or not sha1:
        fallar(f"El bundle no esta firmado o no se pudo leer la firma:\n{salida}")
    return {"dueno": dueno.group(1).strip(), "sha1": sha1.group(1)}


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--sin-build", action="store_true")
    args = p.parse_args()

    if not (APP / "android" / "key.properties").exists():
        fallar(
            "Falta app/android/key.properties: el bundle saldria firmado con la "
            "llave de debug. Ver docs/despliegue.md, 'Firma del APK'."
        )

    nombre, code = version_del_pubspec()
    if not args.sin_build:
        compilar()
    if not AAB.exists():
        fallar(f"No existe {AAB}.")

    f = firma(AAB)
    if "Android Debug" in f["dueno"]:
        fallar("El bundle esta firmado con la llave de DEBUG. No se sube.")

    encontrados = permisos(AAB)
    malos = sorted(encontrados & PROHIBIDOS.keys())
    if malos:
        fallar(
            "El bundle trae permisos que Play va a objetar:\n"
            + "\n".join(f"  {m}: {PROHIBIDOS[m]}" for m in malos)
            + "\nRevisar app/android/app/src/play/AndroidManifest.xml."
        )

    print(f"\nListo: {AAB}")
    print(f"  Version:   {nombre} ({code})")
    print(f"  Tamano:    {AAB.stat().st_size / 1e6:.1f} MB")
    print(f"  Firma:     {f['dueno']}")
    print(f"  SHA-1:     {f['sha1']}")
    print("  Permisos:")
    for permiso in sorted(encontrados):
        print(f"    {permiso.removeprefix('android.permission.')}")


if __name__ == "__main__":
    main()
