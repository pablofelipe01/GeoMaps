"""Compara las tablas y campos reales de Airtable contra docs/airtable-schema.md.

Vale la pena tenerlo: alguien renombra un campo en la interfaz de Airtable, el
upsert empieza a fallar en silencio con typecast, y el trabajo de campo de esa
semana no aparece. Este script lo detecta en segundos.
"""
# TODO
