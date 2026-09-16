/// Quien esta usando la app.
///
/// El login con red valida contra Sirius Nomina Core y guarda el hash bcrypt;
/// los siguientes arranques validan contra ese hash y funcionan sin senal
/// hasta `Config.diasMaxOffline`. Pasado el plazo se exige conexion, que es lo
/// unico que ve si la persona sigue activa en nomina.
class SesionState {
  // TODO: entrar(documento, password), salir(), diasDesdeValidacion
}
