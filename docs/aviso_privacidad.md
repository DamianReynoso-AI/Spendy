# Aviso de privacidad integral de SPENDY

Versión 2 · 18/11/2026. Este es el aviso integral; la app muestra la versión
simplificada (lib/config/privacy_texts.dart) al primer inicio y en
Ajustes > Aviso de privacidad. **Pendiente antes de publicar:** completar el
medio de contacto y pedir revisión a una persona con formación legal
(AUD-07).

## 1. Responsable

Zenorbak 2 (Hugo Damián Reynoso Nesme y Julio Augusto Gutiérrez García),
equipo que desarrolla SPENDY. Contacto: `[correo de contacto]` (se fija al
compilar con `--dart-define=SPENDY_PRIVACY_CONTACT=...`).

## 2. Datos personales que se tratan

- Movimientos que registra la persona: tipo, monto, fecha, categoría, método
  de pago, comercio o descripción y notas (datos patrimoniales o financieros).
- Fotos de recibos o tickets, que pueden contener nombre, RFC, domicilio,
  últimos dígitos de tarjeta y otros datos del comercio.
- Presupuestos mensuales por categoría.
- Configuración: PIN (solo su hash), biometría activada, clave de Gemini
  propia (cifrada en el Keystore).

No se piden nombre, correo, teléfono ni se crea ninguna cuenta.

## 3. Finalidades

Primarias (necesarias): registrar y consultar ingresos y gastos, calcular
balances, resúmenes, indicadores y presupuestos, guardar y mostrar los
recibos, y proteger el acceso con PIN o biometría.

Secundaria (opcional, la activa la persona): leer automáticamente el comercio,
la fecha y el total de un recibo con Google Gemini.

No hay finalidades de publicidad, perfilamiento ni venta de datos.

## 4. Dónde se guardan y cuánto tiempo

Todo se guarda solo en el almacenamiento privado del teléfono. SPENDY no tiene
servidores. La app excluye sus datos del respaldo automático de Android y de la
transferencia a otro teléfono. Los datos se conservan hasta que la persona los
borra (uno por uno o con *Restablecer la app*) o desinstala la app. Las copias
temporales de exportaciones y copias de seguridad se borran al abrir la app de
nuevo. Las copias de seguridad cifradas que la persona guarde fuera de la app
quedan bajo su control.

## 5. Transferencias y encargados

- **Google (Gemini API)**, solo si la persona agrega su propia clave: se envía
  la foto completa del recibo por HTTPS. Google puede procesarla fuera de
  México. La relación es entre la persona y Google, según la cuenta con la que
  creó la clave: en el plan gratuito de Google AI Studio, Google puede usar el
  contenido para mejorar sus productos y personas revisoras pueden leerlo
  (Términos adicionales de la API de Gemini, servicios no pagados).
- **Google ML Kit**, cuando la lectura es en el teléfono: la foto no sale del
  teléfono; Google puede recibir métricas técnicas de uso del servicio.
- Ningún otro tercero recibe datos.

## 6. Derechos ARCO y revocación del consentimiento

Como los datos están solo en el teléfono de la persona, puede ejercer sus
derechos directamente en la app:

- **Acceso:** Movimientos, Resumen anual y exportación CSV/PDF.
- **Rectificación:** editar cualquier movimiento.
- **Cancelación:** eliminar movimientos o *Ajustes > Restablecer la app*.
- **Oposición / revocación:** quitar la clave de Gemini en Ajustes (detiene
  los envíos a Google) o no usar la lectura de recibos.

Para dudas o solicitudes, escribir al contacto del responsable.

## 7. Cambios a este aviso

Cada cambio sube la versión del aviso; la app lo vuelve a mostrar y pide
aceptarlo antes de continuar.
