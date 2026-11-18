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

  /// `true` si se compiló con un servicio de OCR en la nube
  /// (`SPENDY_OCR_ENDPOINT`). Si no, por omisión la lectura se hace en el
  /// teléfono con Google ML Kit y la foto no sale del teléfono. Gemini se
  /// activa después, en Ajustes, con la clave de la persona.
  static const bool ocrUsesCloud =
      String.fromEnvironment('SPENDY_OCR_ENDPOINT').length > 0;

  /// Párrafo del OCR cuando se lee en la nube (RNF-17).
  static const String cloudOcrParagraph =
      'Cuando escaneas un recibo, solo la imagen de ese recibo se envía, de '
      'forma cifrada (HTTPS), a $ocrProviderName para leer el comercio, '
      'la fecha y el total. Nunca se envían tus montos, notas ni ningún '
      'otro dato tuyo.';

  /// Párrafo del OCR cuando se lee en el teléfono con ML Kit (RNF-17).
  static const String onDeviceOcrParagraph =
      'Cuando escaneas un recibo, el comercio, la fecha y el total se leen '
      'en este mismo teléfono con Google ML Kit. La foto no se envía a '
      'ningún servidor. Nunca se envían tus montos, notas ni ningún otro '
      'dato tuyo.';

  /// Párrafo de Gemini, que la persona activa por su cuenta en Ajustes
  /// con su propia clave (RNF-17, TEC-01; AUD-06).
  static const String geminiOptInParagraph =
      'Lectura con Gemini (opcional). Solo si en Ajustes agregas tu propia '
      'clave de Google AI Studio, la foto completa de cada recibo que '
      'escanees se envía cifrada (HTTPS) a Google (Gemini), cuyos servidores '
      'pueden estar fuera de México, para leer el comercio, la fecha y el '
      'total. Google la trata según tu propia cuenta y sus términos: en el '
      'plan gratuito de AI Studio, Google puede usar lo que envías para '
      'mejorar sus productos y personas revisoras pueden verlo. No escanees '
      'así recibos con datos que no quieras compartir (por ejemplo tu RFC o '
      'domicilio). Quitar la clave detiene los envíos de inmediato.';

  /// Correo o medio de contacto del responsable. Se fija al compilar con
  /// `--dart-define=SPENDY_PRIVACY_CONTACT=...` (AUD-07).
  static const String contact =
      String.fromEnvironment('SPENDY_PRIVACY_CONTACT');

  /// Versión del aviso. Si cambia, la app lo vuelve a mostrar para que la
  /// persona lo acepte (AUD-07).
  static const String version = '2';

  static const String title = 'Aviso de privacidad';

  static const String intro =
      'Antes de empezar, lee cómo cuida SPENDY tu información.';

  static const String _responsible =
      'Responsable: Zenorbak 2 (Hugo Damián Reynoso Nesme y Julio Augusto '
      'Gutiérrez García), equipo que desarrolla SPENDY. '
      '${contact == '' ? 'Puedes escribirnos por los datos de contacto de '
          'la ficha de la app en la tienda.' : 'Contacto: $contact.'}';

  /// Párrafos del aviso simplificado, en orden. El aviso integral está en
  /// docs/aviso_privacidad.md.
  static const List<String> paragraphs = [
    _responsible,
    'Qué datos y para qué: los movimientos, montos, fechas, categorías, '
        'notas y fotos de recibos que tú registras, solo para llevar tus '
        'ingresos y gastos, tus presupuestos y tus resúmenes. No pedimos tu '
        'nombre, correo ni cuenta, y no usamos tus datos para publicidad.',
    'Dónde se guardan: únicamente en el almacenamiento privado de este '
        'teléfono. SPENDY no tiene servidores, no los sube a ninguno y no '
        'los incluye en el respaldo automático de Android. Las fotos de tus '
        'recibos no aparecen en la galería.',
    ocrUsesCloud ? cloudOcrParagraph : onDeviceOcrParagraph,
    'Google ML Kit puede enviar a Google datos técnicos de uso (no tus '
        'fotos ni tus movimientos) para mejorar ese servicio.',
    geminiOptInParagraph,
    'Si no quieres usar la lectura de recibos, puedes registrar tus '
        'movimientos a mano.',
    'Los resúmenes que exportes en CSV o PDF y las copias de seguridad '
        '(cifradas con tu contraseña) se guardan o se comparten solo donde tú '
        'elijas; SPENDY borra su copia temporal la siguiente vez que abres la '
        'app.',
    'Tus derechos (acceso, rectificación, cancelación y oposición): como los '
        'datos están solo en tu teléfono, los ejerces directamente en la app: '
        'consúltalos y corrígelos en Movimientos, bórralos uno por uno o todos '
        'con Restablecer la app, y deja de enviar fotos a Google quitando tu '
        'clave de Gemini. Para cualquier duda, usa el contacto del '
        'responsable.',
    'Si desinstalas la app, se borran todos tus datos de este teléfono; solo '
        'quedan las copias de seguridad que tú hayas guardado.',
    'Si este aviso cambia, la app te lo mostrará de nuevo antes de seguir. '
        'Puedes volver a leerlo cuando quieras en Ajustes > Aviso de '
        'privacidad.',
  ];

  static const String acceptButton = 'Acepto';
}
