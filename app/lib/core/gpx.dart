/// Armador de GPX 1.1.
///
/// Es el unico export que no viene de sirius_agro: agro entrega a un agronomo,
/// que abre Google Earth; GeoMaps entrega tambien a topografia y a quien anda
/// con un GPS de mano, y eso habla GPX.
///
/// Al reves que KML, GPX pone los ejes como atributos nombrados
/// (`<trkpt lat=".." lon="..">`), asi que no se pueden invertir por descuido.
/// Lo que si cuesta: el tiempo va en **UTC con sufijo Z**. Un GPX con hora de
/// Bogota sin zona hace que cualquier lector sume cinco horas al recorrido.
///
/// Tres elementos cubren todo lo que la app genera:
///   `<wpt>` waypoint suelto - `<trk>` recorrido grabado - `<rte>` ruta planeada
class Gpx {
  // TODO: deWaypoints(List<Waypoint>) -> String
  // TODO: deTrazado(Trazado) -> String  (un <trkseg> por corte de senal)
}
