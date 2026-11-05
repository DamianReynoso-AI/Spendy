/// M-12 · Configuración central de SPENDY (RNF-26).
///
/// Único lugar donde viven los límites del sistema. Los validadores y las
/// pantallas leen estos valores; nunca se escriben los números a mano.
class AppConfig {
  AppConfig._(); // No se crea ningún objeto: solo agrupa constantes.

  /// Monto máximo permitido en pesos (RF-04).
  static const double maxAmount = 9999999.99;

  /// El mismo monto máximo en centavos. Se usa para validar porque los
  /// enteros no tienen errores de redondeo.
  static const int maxAmountCents = 999999999;

  /// Longitud máxima del comercio o descripción (RF-01, RF-06).
  static const int maxDescriptionLength = 60;

  /// Longitud máxima de la nota (RF-01, RF-02, RF-06).
  static const int maxNoteLength = 200;
}
