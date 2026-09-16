"""Convertir el mapa que mando topografia en algo que el telefono pueda leer.

Camino: GeoPDF / GeoTIFF / KMZ  ->  reproyectar a EPSG:3857  ->  piramide de
teselas  ->  un solo archivo MBTiles en el bucket.

Por que no corre en el telefono: GDAL necesita binarios del sistema, y cortar
la piramide de un raster grande son minutos de CPU y varios GB de temporales.
Hacerlo en un telefono quemaria la bateria en un lote, que es el peor momento
posible.

Por que tampoco corre dentro de la funcion serverless: Vercel no trae GDAL y
una funcion tiene limite de tiempo y de disco. Este modulo **encola** el
trabajo y marca el mapa como `Procesando`; un worker con GDAL instalado lo
toma, y al terminar marca `Listo` con la URL, o `Fallido` con el error que
imprimio GDAL.

El campo que no se puede perder en el camino es el SRC de origen. Un plano en
MAGNA-SIRGAS (EPSG:3116 o 9377) interpretado como WGS84 se dibuja corrido unos
cientos de metros, abre sin error, y nadie lo nota hasta que alguien camina al
punto equivocado. Si GDAL no encuentra el SRC en el archivo, el mapa se marca
`Fallido` pidiendo que lo declaren a mano: adivinarlo seria peor.
"""

# TODO: encolar(archivo, proyecto, src_declarado) -> codigo_mapa (Procesando)
# TODO: publicar_resultado(codigo_mapa, mbtiles, bbox, zoom_min, zoom_max)
# TODO: marcar_fallido(codigo_mapa, error_gdal)
