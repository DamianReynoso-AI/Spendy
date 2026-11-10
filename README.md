# SPENDY (Zenorbak 2)

App móvil en Flutter para registrar ingresos, egresos y comprobantes fiscales.

## Módulos implementados

| Módulo | Archivos | Estado |
|---|---|---|
| M-12 Configuración y formato | `lib/config/`, `lib/core/formatters.dart`, `lib/core/validators.dart` | Implementado con pruebas unitarias |
| M-13 Errores y bitácora | `lib/core/result.dart`, `lib/core/error_logger.dart` | Incremento 1 (v0.1.0) |
| M-11 Persistencia (SQLite) | `lib/data/` | Incremento 1: base v1, categorías, crear y listar movimientos. Incremento 2 (v0.2.0): editar, eliminar y consulta por mes |
| M-03 Categorías | `lib/modules/categories/` | Incremento 1 |
| M-02 Movimientos | `lib/modules/movements/` | Incremento 1: validar, crear y listar. Incremento 2: editar, eliminar sin dobles bajas y balance del mes (`balance_calculator.dart`) |
| M-01 Interfaz | `lib/app.dart`, `lib/ui/` | Incremento 1: formulario de captura y lista. Incremento 2: pantalla principal con balance del mes, detalle, edición y confirmación de borrado |

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
