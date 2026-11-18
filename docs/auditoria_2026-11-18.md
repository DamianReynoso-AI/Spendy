# Auditoría del 18/11/2026: estado de las correcciones

Informe completo: `reportes/Spendy_Auditoria_2026-11-18.docx` (fuera del repo).
Rama auditada: interfaz-lovable 763e070. Correcciones: rama auditoria-v1.1,
encima de mejoras-v1.1.

| ID | Hallazgo | Estado | Dónde |
|---|---|---|---|
| AUD-01 | Clave de Gemini dentro del APK | Corregido (mejoras-v1.1: clave propia en Ajustes) + CI busca claves. **Rotar la clave vieja: Damian** | ocr_key_service.dart, ci.yml |
| AUD-02 | Release firmado con llave de debug | Corregido: release falla sin `android/key.properties` | build.gradle.kts, docs/firma_release.md |
| AUD-03 | Respaldo automático de Android | Corregido | AndroidManifest.xml, res/xml/data_extraction_rules.xml |
| AUD-04 | Bloqueo del PIN se brinca con el reloj y no escala | Corregido: reloj monótono + 30 s, 1, 5, 15, 60 min | pin_service.dart, uptime_clock.dart, MainActivity.kt |
| AUD-05 | Datos sin cifrar | **Pendiente v1.2** (decisión de Damian) | — |
| AUD-06 | Fotos al nivel gratuito de Gemini | Corregido: opcional con clave propia, aviso y consentimiento al guardar la clave | privacy_texts.dart, settings_screen.dart |
| AUD-07 | Aviso de privacidad incompleto | Corregido en la app (versión 2, en Ajustes); **falta contacto y revisión legal** | privacy_texts.dart, docs/aviso_privacidad.md |
| AUD-08 | Sin control de costos del OCR | Corregido por diseño: ya no hay clave compartida; cada persona usa su cuota | mejoras-v1.1 |
| AUD-09 | APK de diagnóstico | Corregido (mejoras-v1.1 compila sin SPENDY_OCR_DEBUG) | — |
| AUD-10 | Sin migraciones | Corregido (mejoras-v1.1) + v3 | database.dart |
| AUD-11 | Sin respaldo propio | Corregido (mejoras-v1.1, copia cifrada) | backup/ |
| AUD-12 | pubspec.lock ignorado | Corregido (mejoras-v1.1) | — |
| AUD-13 | Permisos de sobra | Corregido | AndroidManifest.xml |
| AUD-14 | Huellas nuevas no se detectan | Corregido: llave del Keystore invalidada por cambios de biometría | biometric_service.dart, MainActivity.kt |
| AUD-15 | Inyección en el recibo | Mitigado (mejoras-v1.1: salida estructurada; la persona confirma) | — |
| AUD-16 | Exportaciones en caché | Corregido: se borran al abrir la app | export_service.dart, main.dart |
| AUD-17 | Respuesta del OCR sin límite | Corregido: máximo 512 KB | cloud_ocr_adapter.dart |
| AUD-18 | Lista sin paginación | Corregido: páginas de 200 | movement_repository.dart, movement_list_screen.dart |
| AUD-19 | Sin reglas en la base | Corregido: migración v3 con disparadores | migrations/v3_integrity.dart |
| AUD-20 | Telemetría de ML Kit no avisada | Corregido en el aviso | privacy_texts.dart |
| AUD-21 | Sin CI | Corregido (mejoras-v1.1) + calidad y búsqueda de claves | ci.yml |
| AUD-22 | GitHub y Google Cloud no revisados | **Damian**: protección de main, secret scanning, restricciones de la clave | — |

Sin probar en teléfono: reloj monótono, llave biométrica, manifiesto final en
un dispositivo. Ver la lista de lanzamiento del informe.
