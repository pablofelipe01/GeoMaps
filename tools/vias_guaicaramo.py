# -*- coding: utf-8 -*-
"""Genera app/assets/zonas/guaicaramo-vias.json: las vias del predio.

    python tools/vias_guaicaramo.py "<ruta>/vias.kmz"

El KMZ lo manda topografia del cliente: las vias del predio con sus atributos de
SIG (tipo de rodadura, interna o externa, zona, bloque y parcela a la que
sirven).

## Por que no se guarda como GeoJSON

Porque va adentro del APK y se parsea en un telefono barato con la app abriendo.
Un GeoJSON de estas vias pesa 631 KB, y la mayor parte es sintaxis repetida
("type", "Feature", "geometry", "coordinates") mas doce atributos por via que la
app no usa. Aca se guardan solo los cuatro que se dibujan o se muestran, y las
coordenadas van en un array plano de numeros.

## Que se conserva de cada via

- **tipo**: decide como se dibuja. La distincion que importa es `Proyectada`:
  son vias que **todavia no existen**. Dibujarlas igual que las demas manda a
  alguien a buscar una entrada que no esta construida, que en un predio de
  miles de hectareas es un rodeo de kilometros.
- **interna**: si es del predio o de afuera.
- **cod_bp**: el bloque y la parcela a la que sirve, para poder decir "estas
  sobre la via del B.10-P.9". El numero de parcela se repite entre bloques, asi
  que el codigo completo es lo unico que identifica.

Las coordenadas se redondean a 6 decimales (~0,1 m). Mas precision no la resuelve
ni el GPS del telefono ni la pantalla.
"""
import json
import os
import re
import sys
import zipfile

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, '..'))
DESTINO = os.path.join(RAIZ, 'app', 'assets', 'zonas', 'guaicaramo-vias.json')

# La conversion de referencia que ya hizo map-security desde el mismo KMZ. Se usa
# solo para control: si los conteos no coinciden, uno de los dos lee mal.
REFERENCIA = os.path.normpath(
    os.path.join(RAIZ, '..', 'map-security', 'public', 'vias-guaicaramo.geojson')
)

DECIMALES = 6

RE_PM = re.compile(r'<Placemark.*?</Placemark>', re.S)
RE_COORDS = re.compile(r'<coordinates>(.*?)</coordinates>', re.S)


def main():
    if len(sys.argv) < 2:
        sys.exit('uso: python tools/vias_guaicaramo.py <vias.kmz>')

    kml = leer_kml(sys.argv[1])
    vias = [v for v in (leer_via(pm) for pm in RE_PM.findall(kml)) if v]
    print('vias leidas:', len(vias))

    tipos = sorted({v['tipo'] for v in vias})
    print('tipos:', ', '.join(tipos))
    internas = sum(1 for v in vias if v['interna'])
    print('internas: %d   externas: %d' % (internas, len(vias) - internas))
    vertices = sum(len(v['coords']) // 2 for v in vias)
    print('vertices:', vertices)

    verificar(vias, vertices)
    escribir(vias, tipos)


def leer_kml(ruta):
    with zipfile.ZipFile(ruta) as z:
        nombre = next((n for n in z.namelist() if n.endswith('.kml')), None)
        if not nombre:
            sys.exit('el KMZ no trae ningun .kml adentro')
        return z.read(nombre).decode('utf-8', errors='replace')


def leer_via(pm):
    m = RE_COORDS.search(pm)
    if not m:
        return None

    coords = []
    for trio in m.group(1).split():
        partes = trio.split(',')
        if len(partes) < 2:
            continue
        # KML va lon,lat[,alt]. La altura del KMZ es 0 en todo el archivo y no
        # aporta nada, asi que se descarta.
        coords.append(round(float(partes[0]), DECIMALES))
        coords.append(round(float(partes[1]), DECIMALES))

    # Una "via" de un solo punto no se puede dibujar y no existe en el plano.
    if len(coords) < 4:
        return None

    return {
        'tipo': campo(pm, 'TIPO') or 'Balastrada',
        'interna': campo(pm, 'CODIGO') != 'Externa',
        'cod_bp': campo(pm, 'COD_BP') or '',
        'coords': coords,
    }


def campo(pm, nombre):
    m = re.search(r'<SimpleData name="%s">(.*?)</SimpleData>' % nombre, pm, re.S)
    if not m:
        return ''
    valor = m.group(1).strip()
    # El export de ArcGIS deja nulos escritos como texto; son vacio, no un dato.
    if valor.startswith('<![CDATA['):
        valor = valor[9:-3].strip()
    return '' if valor == '<Null>' else valor


def verificar(vias, vertices):
    """Control cruzado contra la conversion que ya hizo map-security."""
    print()
    print('--- control: contra map-security/public/vias-guaicaramo.geojson ---')
    if not os.path.exists(REFERENCIA):
        print('    (no esta la referencia, se salta)')
        return

    ref = json.load(open(REFERENCIA, encoding='utf-8'))['features']
    ref_vertices = sum(len(f['geometry']['coordinates']) for f in ref)
    print('    vias      aca %4d   referencia %4d' % (len(vias), len(ref)))
    print('    vertices  aca %5d  referencia %5d' % (vertices, ref_vertices))

    if abs(len(vias) - len(ref)) > 5:
        print('    OJO: la diferencia de vias es grande, revisar el parseo')


def escribir(vias, tipos):
    # Los tipos se guardan una vez y cada via los referencia por indice. Son seis
    # cadenas repetidas una vez por via; por indice son numeros de un digito.
    indice = {t: i for i, t in enumerate(tipos)}

    datos = {
        '_fuente': 'KMZ de topografia del cliente. CONFIDENCIAL, no versionar.',
        '_generado': 'tools/vias_guaicaramo.py -- no editar a mano',
        'tipos': tipos,
        'vias': [
            {
                't': indice[v['tipo']],
                'i': 1 if v['interna'] else 0,
                'b': v['cod_bp'],
                'c': v['coords'],
            }
            for v in vias
        ],
    }

    os.makedirs(os.path.dirname(DESTINO), exist_ok=True)
    with open(DESTINO, 'w', encoding='utf-8') as f:
        json.dump(datos, f, ensure_ascii=False, separators=(',', ':'))

    print()
    print('escrito %s (%.0f KB)'
          % (DESTINO, os.path.getsize(DESTINO) / 1024))


if __name__ == '__main__':
    main()
