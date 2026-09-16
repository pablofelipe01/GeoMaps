# tools — conversion de mapas

Aca viven los comandos de GDAL que convierten lo que manda topografia en el
MBTiles que lee el telefono. **No corren en Vercel ni en el telefono**: Vercel
no trae GDAL y una funcion serverless no tiene ni el tiempo ni el disco para
cortar la piramide de un raster de 2 GB.

Se usan de dos formas: el worker los invoca, y una persona los corre a mano
cuando el archivo es demasiado grande para pasar por el endpoint.

## Requisito

GDAL 3.8+ con soporte de PDF. En Windows, lo mas simple es conda:

```bash
conda install -c conda-forge gdal
gdalinfo --formats | grep -i pdf     # tiene que aparecer PDF
```

## GeoPDF -> MBTiles

```bash
# 1. Ver que trae el archivo. Lo que se busca es el SRC y si tiene capas.
gdalinfo entrada.pdf

# 2. Rasterizar a GeoTIFF en Web Mercator.
#    -dpi 300 porque por debajo de eso el texto del plano no se lee al hacer
#    zoom, que es justo para lo que se carga un plano de topografia.
gdal_translate -of GTiff --config GDAL_PDF_DPI 300 entrada.pdf paso1.tif

# 3. Reproyectar. -s_srs SOLO si el archivo no declara el suyo; si lo declara,
#    forzarlo a mano es como se corren los mapas unos cientos de metros.
gdalwarp -t_srs EPSG:3857 -r bilinear paso1.tif paso2.tif

# 4. Cortar la piramide y empacar en MBTiles.
gdal_translate -of MBTILES paso2.tif salida/mapa.mbtiles
gdaladdo -r average salida/mapa.mbtiles 2 4 8 16 32
```

El `gdaladdo` no es opcional: sin los niveles bajos, alejar el mapa en el
telefono deja la pantalla en blanco.

## GeoTIFF -> MBTiles

Igual, desde el paso 3.

## KMZ -> GeoJSON

Para las capas vectoriales (vias, linderos). Se sirven como GeoJSON, no como
teselas: son pocos KB y se dibujan encima de cualquier mapa base.

```bash
ogr2ogr -f GeoJSON salida/vias.geojson entrada.kmz
```

`map-security` tiene un conversor sin dependencias para este caso
(`scripts/kmz-a-geojson.mjs`) si no se quiere instalar GDAL solo para esto.

## Verificar antes de publicar

```bash
gdalinfo salida/mapa.mbtiles     # bbox en WGS84, zoom min y max
```

Ese bbox y esos zooms son los que van a la ficha del mapa en Airtable. Si no
coinciden con lo que la app tiene registrado, el encuadre inicial abre en el
lugar equivocado.
