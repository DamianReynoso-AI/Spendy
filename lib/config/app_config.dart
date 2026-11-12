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

  /// Tamaño máximo de la imagen de un recibo ya comprimida: 1.5 MB
  /// (RNF-12, CA-043).
  static const int maxReceiptBytes = 1572864;

  /// Lado mayor, en píxeles, con el que se guarda un recibo. Es suficiente
  /// para leerlo a simple vista y para el OCR.
  static const int receiptMaxSidePx = 2400;

  /// Calidades JPEG que se prueban, de mayor a menor, hasta que la imagen
  /// cabe en [maxReceiptBytes].
  static const List<int> receiptJpegQualities = [90, 80, 70, 60, 50];

  /// Espacio libre extra que se pide antes de escribir una imagen, para no
  /// dejar el teléfono sin espacio (RF-22).
  static const int freeSpaceMarginBytes = 1048576;
}
