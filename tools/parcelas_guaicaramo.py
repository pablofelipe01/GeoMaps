# -*- coding: utf-8 -*-
"""Genera app/assets/zonas/guaicaramo-parcelas.json: los lotes del predio.

    pip install pypdf shapely
    python tools/parcelas_guaicaramo.py "<ruta>/Acopios Guaicaramo 2026.pdf"

Son los **poligonos de parcela reales** de la capa `PARCELA` del plano del
Departamento Agronomico, cada uno con el codigo de bloque y parcela al que
pertenece. No son las etiquetas sueltas del KMZ: esas son puntos, sin contorno,
y un punto no dice donde termina el lote.

Del parser de map-security (`scripts/pdf-acopios-a-geojson.py`) se reutiliza
todo: el recorte de los anillos y el emparejamiento de cada lote con su rotulo,
que no es directo —un rotulo puede venir partido en dos lineas, y a veces cae
adentro del anillo el rotulo del lote vecino—. Reimplementar eso aca seria tener
dos versiones de la misma decision.

## Que va al asset

- **contorno** del lote, simplificado a 3 m.
- **codigo** completo (`B.10-P.9`). El numero de parcela se repite entre bloques
  —hay un `P.10` en el B.4 y otro en el B.5—, asi que a secas no identifica.
- **bloque** (`B.10`), para poder rotular de lejos sin encimar cientos de
  etiquetas de parcela.
- **hectareas**, que es como se habla de un lote en campo.

Ojo con los codigos: son **del plano 2026**, que renombro lotes que el KMZ de
topografia todavia llama por codigo viejo. El codigo es contexto para ubicarse,
no una clave contra la cual cruzar datos.
"""
import io
import json
import math
import os
import re
import sys

try:
    from shapely.geometry import Polygon
except ImportError:
    sys.exit('falta shapely: pip install shapely')

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, '..'))
DESTINO = os.path.join(RAIZ, 'app', 'assets', 'zonas', 'guaicaramo-parcelas.json')

MAP_SECURITY = os.path.normpath(os.path.join(RAIZ, '..', 'map-security'))
PARSER = os.path.join(MAP_SECURITY, 'scripts', 'pdf-acopios-a-geojson.py')
ETIQUETAS = os.path.join(
    MAP_SECURITY, 'public', 'vias-guaicaramo-etiquetas.geojson'
)

# El corte se hace justo antes de los acopios: para entonces el parser ya
# resolvio `parcelas` y `cod_parcela`, que es todo lo que hace falta.
CORTE = '# --- acopios ---'

DECIMALES = 6
TOLERANCIA_M = 3

M_POR_GRADO_LAT = 110540.0
RE_BP = re.compile(r'^B\.(\d+)-P\.(\d+)')


def main():
    if len(sys.argv) < 2:
        sys.exit('uso: python tools/parcelas_guaicaramo.py <plano.pdf>')

    anillos, codigos = leer_parcelas(sys.argv[1])
    print('parcelas:', len(anillos))
    print('con codigo:', sum(1 for i in range(len(anillos)) if limpiar(codigos.get(i))))

    parcelas = armar(anillos, codigos)
    bloques = agrupar_bloques(parcelas)
    print('bloques:', len(bloques))
    print('hectareas:', round(sum(p['ha'] for p in parcelas), 1))

    verificar(parcelas, bloques)
    escribir(parcelas, bloques)


def leer_parcelas(pdf):
    if not os.path.exists(PARSER):
        sys.exit('no esta el parser de map-security en %s' % PARSER)

    codigo = open(PARSER, encoding='utf-8').read()
    prefijo = codigo.split(CORTE)[0]
    if prefijo == codigo:
        sys.exit('el parser cambio de forma: ya no esta el corte "%s"' % CORTE)

    sys.argv = [PARSER, pdf]
    ambito = {'__file__': PARSER, '__name__': 'parser_map_security'}
    real, sys.stdout = sys.stdout, io.StringIO()
    try:
        exec(compile(prefijo, PARSER, 'exec'), ambito)
    finally:
        sys.stdout = real

    return ambito['parcelas'], ambito['cod_parcela']


def armar(anillos, codigos):
    lat_media = sum(p[1] for an in anillos for p in an) / sum(
        len(an) for an in anillos
    )
    m_por_grado_lon = 111320.0 * math.cos(math.radians(lat_media))
    m2_por_grado2 = M_POR_GRADO_LAT * m_por_grado_lon
    tolerancia = TOLERANCIA_M / ((M_POR_GRADO_LAT + m_por_grado_lon) / 2)

    parcelas = []
    for i, an in enumerate(anillos):
        forma = Polygon(an)
        if not forma.is_valid:
            # Un anillo que se cruza a si mismo. buffer(0) lo endereza, pero
            # puede partirlo en varios pedazos: se conserva el mayor, que es el
            # lote, y se descartan las astillas del cruce. Sin esto se perdia
            # un lote entero.
            forma = forma.buffer(0)
            if forma.geom_type == 'MultiPolygon':
                forma = max(forma.geoms, key=lambda g: g.area)
        if forma.is_empty or forma.geom_type != 'Polygon':
            print('  lote %d descartado: geometria irrecuperable' % i)
            continue

        forma = forma.simplify(tolerancia)
        coords = []
        for x, y in forma.exterior.coords:
            coords.append(round(x, DECIMALES))
            coords.append(round(y, DECIMALES))

        cod = limpiar(codigos.get(i))
        m = RE_BP.match(cod) if cod else None
        centro = forma.representative_point()

        parcelas.append({
            'cod': cod,
            'bloque': 'B.' + m.group(1) if m else '',
            'ha': round(forma.area * m2_por_grado2 / 10000, 2),
            'lon': round(centro.x, DECIMALES),
            'lat': round(centro.y, DECIMALES),
            'coords': coords,
        })

    return parcelas


def limpiar(cod):
    """El rotulo tal como sale del plano, recortado a lo que identifica al lote.

    Dos formas conviven en el plano 2026 y las dos son validas:

    - **Codigo**: "B.6-P.4 (R.)". La marca de renovacion viene en otra linea del
      rotulo y para ubicarse no aporta, asi que se recorta al codigo.
    - **Nombre propio**: "Lejanias", "Chiguiros 2 (R.)", "Guarataro". Son 27
      lotes que el plano 2026 renombro y que el KMZ de topografia todavia llama
      por codigo. El nombre se conserva entero: es como los llama la gente que
      trabaja ahi, y truncarlo dejaria "Chiguiros" para tres lotes distintos.
    """
    if not cod:
        return ''
    m = RE_BP.match(cod.strip())
    return m.group(0) if m else cod.strip()


def agrupar_bloques(parcelas):
    """Un punto por bloque, para rotular de lejos.

    Sin esto, alejarse el mapa dibuja cientos de codigos de parcela encimados que
    no se leen. El bloque es la unidad con la que se habla de lejos, y son un
    orden de magnitud menos.
    """
    por_bloque = {}
    for p in parcelas:
        if p['bloque']:
            por_bloque.setdefault(p['bloque'], []).append(p)

    bloques = []
    for nombre, ps in sorted(por_bloque.items()):
        # El centro del bloque se pondera por area: un bloque con un lote chico
        # colgando de un costado no puede llevar la etiqueta sobre ese lote.
        peso = sum(p['ha'] for p in ps) or len(ps)
        bloques.append({
            'b': nombre,
            'lon': round(sum(p['lon'] * (p['ha'] or 1) for p in ps) / peso, DECIMALES),
            'lat': round(sum(p['lat'] * (p['ha'] or 1) for p in ps) / peso, DECIMALES),
            'ha': round(sum(p['ha'] for p in ps), 1),
            'n': len(ps),
        })
    return bloques


def verificar(parcelas, bloques):
    """Control contra los rotulos del KMZ, que es otra fuente y otro ano."""
    print()
    print('--- control: contra las etiquetas del KMZ de topografia ---')
    if not os.path.exists(ETIQUETAS):
        print('    (no estan las etiquetas, se salta)')
        return

    feats = json.load(open(ETIQUETAS, encoding='utf-8'))['features']
    kmz_bloques = {f['properties'].get('texto') for f in feats
                   if f['properties'].get('clase') == 'bloque'}
    kmz_parcelas = {f['properties'].get('cod_bp') for f in feats
                    if f['properties'].get('clase') == 'parcela'}
    kmz_bloques.discard(None)
    kmz_parcelas.discard(None)

    mios_b = {b['b'] for b in bloques}
    mios_p = {p['cod'] for p in parcelas if p['cod']}

    print('    bloques   plano %3d   KMZ %3d   coinciden %3d'
          % (len(mios_b), len(kmz_bloques), len(mios_b & kmz_bloques)))
    print('    parcelas  plano %3d   KMZ %3d   coinciden %3d'
          % (len(mios_p), len(kmz_parcelas), len(mios_p & kmz_parcelas)))
    print('    (el plano 2026 renombro lotes que el KMZ llama por codigo viejo:')
    print('     la diferencia es esperable y esta explicada en tools/README.md)')

    nombrados = [p['cod'] for p in parcelas
                 if p['cod'] and not RE_BP.match(p['cod'])]
    print()
    print('--- lotes con nombre propio en vez de codigo:', len(nombrados), '---')
    print('   ', ', '.join(sorted(nombrados)[:6]), '...')

    # El emparejamiento rotulo-lote es por cercania y no es perfecto: el propio
    # script de map-security reporta un par repetido entre los acopios. Un par
    # de codigos repetidos se tolera; si el numero crece, el emparejamiento se
    # desalineo y hay que mirarlo antes de publicar el asset.
    vistos, repetidos = set(), []
    for p in parcelas:
        if not p['cod']:
            continue
        if p['cod'] in vistos:
            repetidos.append(p['cod'])
        vistos.add(p['cod'])
    print('--- codigos repetidos en dos lotes:', len(repetidos), '---')
    if repetidos:
        print('   ', ', '.join(sorted(repetidos)))
    if len(repetidos) > 5:
        print('    OJO: son muchos, el emparejamiento de rotulos se desalineo')


def escribir(parcelas, bloques):
    datos = {
        '_fuente': 'Plano del Departamento Agronomico, capa PARCELA. '
                   'CONFIDENCIAL, no versionar.',
        '_generado': 'tools/parcelas_guaicaramo.py -- no editar a mano',
        'parcelas': [
            {
                'p': p['cod'],
                'b': p['bloque'],
                'h': p['ha'],
                'x': p['lon'],
                'y': p['lat'],
                'c': p['coords'],
            }
            for p in parcelas
        ],
        'bloques': bloques,
    }

    os.makedirs(os.path.dirname(DESTINO), exist_ok=True)
    with open(DESTINO, 'w', encoding='utf-8') as f:
        json.dump(datos, f, ensure_ascii=False, separators=(',', ':'))

    vertices = sum(len(p['coords']) // 2 for p in parcelas)
    print()
    print('escrito %s (%.0f KB, %d vertices)'
          % (DESTINO, os.path.getsize(DESTINO) / 1024, vertices))


if __name__ == '__main__':
    main()
