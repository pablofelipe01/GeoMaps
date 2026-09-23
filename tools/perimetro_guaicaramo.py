# -*- coding: utf-8 -*-
"""Genera app/assets/zonas/guaicaramo.json: el perimetro de la plantacion.

    pip install pypdf shapely
    python tools/perimetro_guaicaramo.py "<ruta>/Acopios Guaicaramo 2026.pdf"

## De donde sale el dato

El plano *Acopios Guaicaramo* del Departamento Agronomico es un PDF geoespacial
y trae, en su capa `PARCELA`, los lotes cerrados de la plantacion. Ese es el
unico dato duro que existe del predio: no hay un archivo con "el borde" en
ningun lado.

El parseo del PDF no se reimplementa aca. Se reutiliza el de map-security
(`scripts/pdf-acopios-a-geojson.py`), ejecutando su prefijo -todo lo que llena
el diccionario `figuras`- y tomando `figuras['PARCELA']`. Si ese script cambia
de forma, esto se entera al fallar, que es mejor que tener dos parsers del mismo
PDF divergiendo en silencio.

## Del monton de lotes a un perimetro

Los lotes sueltos no sirven para preguntar "estoy dentro": entre dos lotes hay
una via o un canal, y alguien parado en la via de su propio bloque quedaria
fuera de la plantacion. Por eso, en orden:

1. **Union** de los poligonos de parcela.
2. **Cierre de 120 m** (dilatar y volver a contraer). Cose los lotes separados
   por vias y canales internos sin inflar el borde exterior, que es lo que pasa
   si solo se dilata.
3. **Margen de 50 m** hacia afuera. El borde de un lote no es una pared, y el
   GPS de un telefono de campo tiene decenas de metros de error bajo el dosel.
   Sin el margen, la funcion se apagaria sola caminando el lindero.
4. **Simplificacion a 15 m**. El detalle fino no cambia la respuesta y cada
   vertice se paga en el telefono.

Queda un puñado de sectores y unos cientos de vertices, en pocos KB. Los
numeros exactos los imprime el script al correr.

## Como se verifica que quedo bien

Lo imprime el propio script, contra fuentes que no participaron del calculo:

- Los **acopios** del plano tienen que caer dentro, y caen todos menos uno.
- Las vias del KMZ de topografia separan `Interna` de `Externa`. Las internas
  caen dentro casi todas; las externas, casi ninguna. Ese contraste es lo que muestra
  que el perimetro discrimina de verdad, y no que sea una mancha que traga todo.
- Villavicencio, Bogota, Puerto Gaitan y el casco de Barranca de Upia quedan
  afuera.
"""
import io
import json
import math
import os
import sys

try:
    from shapely.geometry import MultiPolygon, Point, Polygon
    from shapely.ops import unary_union
except ImportError:
    sys.exit('falta shapely: pip install shapely')

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, '..'))
DESTINO = os.path.join(RAIZ, 'app', 'assets', 'zonas', 'guaicaramo.json')

# El parser del PDF y las dos fuentes de control viven en el repo de al lado.
MAP_SECURITY = os.path.normpath(os.path.join(RAIZ, '..', 'map-security'))
PARSER = os.path.join(MAP_SECURITY, 'scripts', 'pdf-acopios-a-geojson.py')
ACOPIOS = os.path.join(MAP_SECURITY, 'public', 'acopios-guaicaramo.geojson')
VIAS = os.path.join(MAP_SECURITY, 'public', 'vias-guaicaramo.geojson')

# Los tres numeros que definen el perimetro. Estan arriba para poder moverlos
# sin leer el resto: cambiarlos cambia donde se prende la funcion en el campo.
CIERRE_M = 120
MARGEN_M = 50
TOLERANCIA_M = 15

M_POR_GRADO_LAT = 110540.0


def main():
    if len(sys.argv) < 2:
        sys.exit('uso: python tools/perimetro_guaicaramo.py <plano.pdf>')
    pdf = sys.argv[1]

    anillos = leer_parcelas(pdf)
    print('parcelas cerradas > 0.2 ha:', len(anillos))

    perimetro, m2_por_grado2 = armar_perimetro(anillos)
    sectores = sorted(
        (list(p.exterior.coords) for p in perimetro.geoms),
        key=lambda c: -Polygon(c).area,
    )

    print()
    for i, c in enumerate(sectores):
        ha = Polygon(c).area * m2_por_grado2 / 10000
        print('  sector %d: %8.1f ha  %4d vertices' % (i, ha, len(c)))

    # Lo que va al asset son los contornos exteriores. Un hueco adentro del
    # predio no cambia la respuesta util: quien esta parado ahi esta en la
    # plantacion igual.
    solo_exteriores = MultiPolygon([Polygon(c) for c in sectores])
    verificar(solo_exteriores)
    escribir(sectores, solo_exteriores.bounds)


def leer_parcelas(pdf):
    """Los anillos de la capa PARCELA, via el parser de map-security."""
    if not os.path.exists(PARSER):
        sys.exit('no esta el parser de map-security en %s' % PARSER)

    codigo = open(PARSER, encoding='utf-8').read()
    prefijo = codigo.split('# ============== 2. armar los acopios')[0]
    if prefijo == codigo:
        sys.exit('el parser cambio de forma: ya no esta el corte de la seccion 2')

    # El parser lee sys.argv y habla por stdout; se le da el PDF y se lo calla.
    sys.argv = [PARSER, pdf]
    ambito = {'__file__': PARSER, '__name__': 'parser_map_security'}
    real, sys.stdout = sys.stdout, io.StringIO()
    try:
        exec(compile(prefijo, PARSER, 'exec'), ambito)
    finally:
        sys.stdout = real

    figuras = ambito['figuras']
    # Mismo filtro que usa el parser para resolver en que lote cae cada acopio.
    return [sp for it in figuras['PARCELA'] for sp in it['p']
            if len(sp) > 3 and sp[0] == sp[-1] and area_m2(sp) > 2000]


def armar_perimetro(anillos):
    poligonos = []
    for an in anillos:
        p = Polygon(an)
        if not p.is_valid:
            # Un anillo que se cruza a si mismo; buffer(0) lo endereza.
            p = p.buffer(0)
        if not p.is_empty:
            poligonos.append(p)

    union = unary_union(poligonos)
    m_por_grado_lon = 111320.0 * math.cos(math.radians(union.centroid.y))
    m2_por_grado2 = M_POR_GRADO_LAT * m_por_grado_lon

    def grados(metros):
        return metros / ((M_POR_GRADO_LAT + m_por_grado_lon) / 2)

    cerrado = union.buffer(grados(CIERRE_M)).buffer(-grados(CIERRE_M))
    final = cerrado.buffer(grados(MARGEN_M)).simplify(grados(TOLERANCIA_M))
    if final.geom_type == 'Polygon':
        final = MultiPolygon([final])

    print('parcelas: %.1f ha    perimetro: %.1f ha'
          % (union.area * m2_por_grado2 / 10000,
             final.area * m2_por_grado2 / 10000))
    return final, m2_por_grado2


def verificar(perimetro):
    """Los tres controles, contra fuentes que no entraron en el calculo."""
    print()
    print('--- control: los acopios del plano caen dentro ---')
    acopios = cargar(ACOPIOS)
    if acopios:
        dentro = sum(
            perimetro.contains(Point(*f['geometry']['coordinates'][:2]))
            for f in acopios
        )
        print('    %d de %d' % (dentro, len(acopios)))

    print('--- control: internas adentro, externas afuera ---')
    vias = cargar(VIAS)
    if vias:
        for codigo in ('Interna', 'Externa'):
            sel = [f for f in vias if f['properties'].get('CODIGO') == codigo]
            puntos = [p for f in sel for p in f['geometry']['coordinates']]
            if not puntos:
                continue
            dentro = sum(perimetro.contains(Point(lon, lat)) for lon, lat in puntos)
            print('    %-8s %6d vertices  %5.1f%% dentro'
                  % (codigo, len(puntos), 100 * dentro / len(puntos)))

    print('--- control: lugares que tienen que quedar afuera ---')
    for nombre, (lat, lon) in {
        'Villavicencio': (4.1420, -73.6266),
        'Bogota': (4.7110, -74.0721),
        'Barranca de Upia': (4.5686, -72.9678),
        'Puerto Gaitan': (4.3131, -72.0800),
    }.items():
        marca = 'ADENTRO (mal)' if perimetro.contains(Point(lon, lat)) else 'afuera'
        print('    %-20s %s' % (nombre, marca))


def escribir(sectores, bbox):
    datos = {
        '_fuente': 'Plano del Departamento Agronomico, capa PARCELA: los lotes '
                   'unidos con un cierre de %d m y un margen de %d m hacia '
                   'afuera. CONFIDENCIAL, no versionar.'
                   % (CIERRE_M, MARGEN_M),
        '_generado': 'tools/perimetro_guaicaramo.py -- no editar a mano',
        'nombre': 'Guaicaramo',
        'bbox': [round(v, 6) for v in bbox],
        'sectores': [[[round(x, 6), round(y, 6)] for x, y in c] for c in sectores],
    }

    os.makedirs(os.path.dirname(DESTINO), exist_ok=True)
    with open(DESTINO, 'w', encoding='utf-8') as f:
        json.dump(datos, f, ensure_ascii=False, separators=(',', ':'))

    print()
    print('escrito %s (%.1f KB, %d vertices)'
          % (DESTINO, os.path.getsize(DESTINO) / 1024,
             sum(len(c) for c in sectores)))


def cargar(ruta):
    if not os.path.exists(ruta):
        print('    (no esta %s, se salta)' % ruta)
        return None
    return json.load(open(ruta, encoding='utf-8'))['features']


def area_m2(anillo):
    """Area de un anillo en metros cuadrados, plano local."""
    k = 111320.0 * math.cos(math.radians(sum(p[1] for p in anillo) / len(anillo)))
    a = 0.0
    for i in range(len(anillo) - 1):
        a += (anillo[i][0] * k * anillo[i + 1][1] * M_POR_GRADO_LAT
              - anillo[i + 1][0] * k * anillo[i][1] * M_POR_GRADO_LAT)
    return abs(a) / 2


if __name__ == '__main__':
    main()
