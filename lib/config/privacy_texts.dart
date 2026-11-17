/// M-12 · Texto único del aviso de privacidad (RF-51; RNF-17, RNF-51;
/// DUP-04).
///
/// Español de México y lenguaje claro. Es el único lugar donde vive este
/// texto: la pantalla de primer inicio lo lee de aquí.
library;

/// Textos del aviso de privacidad.
class PrivacyTexts {
  PrivacyTexts._();

  /// Nombre del proveedor de OCR que se muestra en el aviso. Se fija al
  /// compilar con `--dart-define=SPENDY_OCR_PROVIDER_NAME=...` cuando el
  /// equipo lo defina (TEC-01); mientras tanto se usa una descripción
  /// genérica.
  static const String ocrProviderName = String.fromEnvironment(
    'SPENDY_OCR_PROVIDER_NAME',
    defaultValue: 'un servicio externo de lectura de recibos (OCR)',
  );

  static const String title = 'Aviso de privacidad';

  static const String intro =
      'Antes de empezar, lee cómo cuida SPENDY tu información.';

  /// Párrafos del aviso, en orden.
  static const List<String> paragraphs = [
    'Tus movimientos, notas y fotos de recibos se guardan únicamente en el '
        'almacenamiento privado de este teléfono. SPENDY no los sube a '
        'ningún servidor ni los comparte con nadie.',
    'Las fotos de tus recibos no aparecen en la galería del teléfono.',
    'Cuando escaneas un recibo, solo la imagen de ese recibo se envía, de '
        'forma cifrada (HTTPS), a $ocrProviderName para leer el comercio, '
        'la fecha y el total. Nunca se envían tus montos, notas ni ningún '
        'otro dato tuyo.',
    'Si no quieres usar la lectura de recibos, puedes registrar tus '
        'movimientos a mano.',
    'Los resúmenes que exportes en CSV o PDF se guardan o se comparten solo '
        'donde tú elijas.',
    'Si desinstalas la app, se borran todos tus datos de este teléfono.',
  ];

  static const String acceptButton = 'Acepto';
}
