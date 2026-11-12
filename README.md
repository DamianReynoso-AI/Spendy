# SPENDY (Zenorbak 2)

App móvil en Flutter para registrar ingresos, egresos y comprobantes fiscales.

## Módulos implementados

| Módulo | Archivos | Estado |
|---|---|---|
| M-12 Configuración y formato | `lib/config/`, `lib/core/formatters.dart`, `lib/core/validators.dart` | Implementado con pruebas unitarias |
| M-13 Errores y bitácora | `lib/core/result.dart`, `lib/core/error_logger.dart` | Incremento 1 (v0.1.0) |
| M-11 Persistencia (SQLite) | `lib/data/` | Incremento 1: base v1, categorías, crear y listar movimientos. Incremento 2 (v0.2.0): editar, eliminar y consulta por mes. Incremento 3: `image_store.dart` (imágenes privadas, `.nomedia`, espacio libre, limpieza de huérfanos), `receipt_repository.dart` y guardado atómico egreso + recibo |
| M-03 Categorías | `lib/modules/categories/` | Incremento 1 |
| M-02 Movimientos | `lib/modules/movements/` | Incremento 1: validar, crear y listar. Incremento 2: editar, eliminar sin dobles bajas y balance del mes (`balance_calculator.dart`) |
| M-04 Recibos y cámara | `lib/modules/receipts/` | Incremento 3 (v0.3.0): permiso de cámara, captura, compresión a 1.5 MB o menos, vincular, reemplazar, quitar y descartar recibos |
| M-01 Interfaz | `lib/app.dart`, `lib/ui/` | Incremento 1: formulario de captura y lista. Incremento 2: pantalla principal con balance del mes, detalle, edición y confirmación de borrado. Incremento 3: pantalla de escaneo con vista previa, foto adjunta en el formulario y recibo con zoom en el detalle |

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
flutter test            # unitarias (test/unit) y de pantallas (test/widget)
flutter test --coverage # reporte en coverage/lcov.info
```

Las pruebas de la base usan SQLite en memoria del equipo (`sqflite_common_ffi`),
así que no necesitan emulador.

Las pruebas también corren solas en GitHub Actions en cada push (pestaña **Actions**).
