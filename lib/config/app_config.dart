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

  /// Tiempo máximo de espera de la lectura OCR: 10 segundos exactos
  /// (RF-30, RNF-26).
  static const Duration ocrTimeout = Duration(seconds: 10);

  /// Meta de tiempo de la lectura OCR en al menos el 90 % de los intentos
  /// (RNF-13, CA-065).
  static const Duration ocrTargetTime = Duration(seconds: 8);

  /// Longitud exacta del PIN de acceso: 6 dígitos (RF-45, CA-115).
  static const int pinLength = 6;

  /// Intentos fallidos consecutivos antes del bloqueo temporal (RF-48,
  /// CA-129, CA-130).
  static const int maxPinAttempts = 5;

  /// Duración del bloqueo tras [maxPinAttempts] fallos: 30 segundos
  /// (RF-48, CA-130, CA-132).
  static const Duration pinLockout = Duration(seconds: 30);

  /// Tiempo en segundo plano a partir del cual se vuelve a pedir el PIN:
  /// más de 60 segundos lo pide, 60 o menos no (RF-46, CA-121, CA-122,
  /// AMB-07).
  static const Duration backgroundLockAfter = Duration(seconds: 60);

  /// Iteraciones de PBKDF2-HMAC-SHA256 al derivar el hash del PIN
  /// (RNF-15, TEC-05). Un PIN de 6 dígitos solo tiene un millón de
  /// combinaciones: el costo frena un ataque fuera de línea, pero la
  /// protección real es el almacén seguro más el límite de intentos.
  static const int pinHashIterations = 100000;

  /// Bytes de la sal criptográfica aleatoria de cada PIN (RNF-15).
  static const int pinSaltBytes = 16;
}
