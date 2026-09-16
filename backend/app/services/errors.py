"""Traduccion de fallas de terceros a respuestas que la app puede entender.

Portado de sirius_agro. La distincion que importa: un 502 con el nombre del
servicio caido le dice al tecnico "reintenta mas tarde"; un 500 generico lo
deja sin saber si perdio el trabajo.
"""

# TODO: UPSTREAM_EXCEPTIONS, upstream_error(servicio, exc)
