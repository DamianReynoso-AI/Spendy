# SPENDY (Zenorbak 2)

App móvil en Flutter para registrar ingresos, egresos y comprobantes fiscales.

## Módulos implementados

| Módulo | Archivos | Estado |
|---|---|---|
| M-12 Configuración y formato | `lib/config/`, `lib/core/formatters.dart`, `lib/core/validators.dart` | Implementado con pruebas unitarias |
| M-13 Errores y bitácora | `lib/core/result.dart`, `lib/core/error_logger.dart` | Incremento 1 (v0.1.0) |
| M-11 Persistencia (SQLite) | `lib/data/` | Incremento 1: base v1, categorías, crear y listar movimientos. Incremento 2 (v0.2.0): editar, eliminar y consulta por mes. Incremento 3: `image_store.dart` (imágenes privadas, `.nomedia`, espacio libre, limpieza de huérfanos), `receipt_repository.dart` y guardado atómico egreso + recibo. Incremento 5: `settings_repository.dart` y consultas anuales. Incremento 6: consulta filtrada `queryFilteredMovements` con placeholders `?` y los índices existentes |
| M-03 Categorías | `lib/modules/categories/` | Incremento 1 |
| M-02 Movimientos | `lib/modules/movements/` | Incremento 1: validar, crear y listar. Incremento 2: editar, eliminar sin dobles bajas y balance del mes (`balance_calculator.dart`) |
| M-04 Recibos y cámara | `lib/modules/receipts/` | Incremento 3 (v0.3.0): permiso de cámara, captura, compresión a 1.5 MB o menos, vincular, reemplazar, quitar y descartar recibos |
| M-05 Lectura OCR | `lib/modules/ocr/` | Incremento 4 (v0.4.0): adaptador `OcrAdapter` (nube por HTTPS y simulado), intérprete y validador de comercio, fecha y total, orquestador con límite de 10 s y cancelación |
| M-07 Resumen anual | `lib/modules/summary/` | Incremento 5 (v0.5.0): selector de años, totales del año y gastos por categoría en centavos; cálculo puro sin Flutter |
| M-08 Exportación | `lib/modules/export/` | Incremento 5: CSV (UTF-8 con BOM) y PDF estándar con los cuatro bloques, nombre `spendy_resumen_AAAA` y menú nativo de compartir |
| M-06 Búsqueda y filtros | `lib/modules/search/` | Incremento 6 (v0.6.0): rango de fechas, categoría, tipo y texto (sin acentos ni mayúsculas, `%` `_` `'` literales) combinados, con conteo y suma; sumas separadas si hay ingresos y egresos |
| M-10 Aviso de privacidad | `lib/modules/privacy/`, `lib/config/privacy_texts.dart` | Incremento 5: pantalla obligatoria de primer inicio; la aceptación se guarda en `ajuste` |
| M-01 Interfaz | `lib/app.dart`, `lib/ui/` | Incremento 1: formulario de captura y lista. Incremento 2: pantalla principal con balance del mes, detalle, edición y confirmación de borrado. Incremento 3: pantalla de escaneo con vista previa, foto adjunta en el formulario y recibo con zoom en el detalle. Incremento 4: botón "Escanear recibo" en la lista, progreso con "Cancelar", diálogos de error e imagen ilegible y pantalla de revisión (`ocr_review_screen.dart`). Incremento 5: aviso de privacidad al primer inicio (`onboarding_screen.dart`) y resumen anual con exportación (`summary_screen.dart`). Incremento 6: barra de filtros en la lista (`filter_bar.dart`), conteo y suma, "Sin resultados" y "Limpiar filtros" |

## Permisos de cámara (incremento 3)

El repositorio todavía no incluye las carpetas `android/` e `ios/`. Al
generarlas con `flutter create --platforms=android,ios .` hay que agregar:

- Android, `android/app/src/main/AndroidManifest.xml`:
  `<uses-permission android:name="android.permission.CAMERA" />`
  (y `minSdkVersion` 21 o mayor, que pide el plugin `camera`).
- iOS, `ios/Runner/Info.plist`: la llave `NSCameraUsageDescription` con el
  texto "SPENDY usa la cámara solo para tomar la foto de tus recibos." y, en
  el `Podfile`, la macro `PERMISSION_CAMERA=1` de `permission_handler`.

Las fotos se guardan en la carpeta privada de la app
(`temp_recibos/` y `recibos/`, cada una con `.nomedia`), nunca en la galería.

## Proveedor de OCR (incremento 4)

El proveedor todavía no está definido (TEC-01, TEC-02). La app usa
`CloudOcrAdapter`, que habla con cualquier servicio HTTPS que cumpla este
contrato:

```text
POST <SPENDY_OCR_ENDPOINT>            (solo https://)
Authorization: Bearer <SPENDY_OCR_API_KEY>
Content-Type: image/jpeg
<bytes de la foto comprimida>

200 OK  {"text": "texto leído del recibo"}
```

La clave nunca va en el código (RNF-18). Se pasa al compilar desde un
archivo local que está en `.gitignore`:

```bash
echo '{"SPENDY_OCR_ENDPOINT": "https://...", "SPENDY_OCR_API_KEY": "..."}' > ocr.env.json
flutter run --dart-define-from-file=ocr.env.json
```

El nombre del proveedor que aparece en el aviso de privacidad se fija con
`--dart-define=SPENDY_OCR_PROVIDER_NAME=...`; mientras no se defina, el aviso
dice "un servicio externo de lectura de recibos (OCR)".

Sin esa configuración la app funciona igual: al escanear avisa que la
lectura no está disponible y abre el registro manual con la foto. Para
cambiar de proveedor basta con otra implementación de `OcrAdapter`
(RNF-32). Las pruebas usan `MockOcrAdapter`; la prueba con los 30 recibos
reales está en `test/integration/receipts_accuracy_test.dart` (ver
`test/fixtures/receipts/README.md`).

## Sin conexión (incremento 6)

Todo funciona sin internet salvo la lectura OCR, que solo avisa y deja
registrar a mano. `test/integration/offline_test.dart` lo comprueba de
forma automática: en `lib/` solo `cloud_ocr_adapter.dart` usa red, y con
toda conexión bloqueada se registra, filtra y resume con SQLite real. La
prueba E2E en modo avión sobre un teléfono real se hace a mano (no hay
dispositivo en el entorno de CI).

## Revisión de calidad

```bash
python3 tool/check_quality.py   # RNF-29 (≤ 50 líneas, complejidad ≤ 10) y RNF-30 (lib/ui no importa lib/data)
```

Es una revisión aproximada hecha con un script; no sustituye a un
analizador de métricas.

## Correr las pruebas

```bash
flutter pub get
flutter analyze
flutter test            # unitarias (test/unit), de pantallas (test/widget) y de flujo (test/integration)
flutter test --coverage # reporte en coverage/lcov.info
```

Las pruebas de la base usan SQLite en memoria del equipo (`sqflite_common_ffi`),
así que no necesitan emulador.

Las pruebas también corren solas en GitHub Actions en cada push (pestaña **Actions**).
