"""Login contra Sirius Nomina Core.

Es la misma mecanica de sirius_agro: se valida el documento contra la tabla
Personal de OTRA base, con un PAT de solo lectura, y se devuelve un hash bcrypt
que el telefono guarda para poder entrar sin senal hasta `dias_max_offline`.

Que sea otro token no es ceremonia: el PAT de GeoMaps no tiene por que poder
leer salarios ni cuentas bancarias.
"""

# TODO: validar(documento, password) -> UsuarioNomina | None
# TODO: rol_desde_orden(orden) -> campo / coordinador / admin
