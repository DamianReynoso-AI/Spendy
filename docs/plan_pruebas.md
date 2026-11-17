# Plan y reporte de pruebas de SPENDY (RNF-50)

| Dato | Registro |
|---|---|
| Proyecto | SPENDY (Zenorbak 2) |
| Integrantes | Gutiérrez García Julio Augusto (Analista y Tester) · Reynoso Nesme Hugo Damián (Operador de IA y Documentador) |
| Versión probada | Rama `cierre-v1` sobre `v0.6.0` (candidata a `v1.0.0`) |
| Fecha de ejecución automatizada | 17/11/2026 |
| Fecha de entrega | 23/11/2026 (pruebas con usuarios previstas el 22/11/2026) |
| Estado | Pruebas automatizadas ejecutadas y aprobadas. **Pendientes de ejecutar por el equipo:** OCR con 30 recibos reales, pruebas en teléfono real (arranque, interrupciones, fuente al 200 %, modo avión) y aceptación con 5 usuarios. Esas secciones tienen la tabla lista y vacía; no se inventaron datos. |

Leyenda de estados: **Aprobado** = ejecutado y cumple; **Fallido** = ejecutado y no cumple;
**Pendiente** = no ejecutado todavía; **Pendiente v0.7.0** = depende del incremento 7 (PIN).

## 1. Estrategia

| Nivel | Qué cubre | Dónde | Cómo se ejecuta |
|---|---|---|---|
| Unitarias | Validadores, formatos, servicios de cada módulo, repositorios con SQLite real en archivo o memoria (`sqflite_common_ffi`) | `test/unit/` (246 pruebas) | `flutter test` |
| De pantallas (widget) | Formularios, lista, detalle, escaneo, revisión OCR, resumen, filtros, accesibilidad y tamaños de pantalla | `test/widget/` (47 pruebas) | `flutter test` |
| De integración | Flujo de escaneo con OCR simulado, sin conexión, rendimiento con 2,000 movimientos, bitácora y OCR real con 30 recibos | `test/integration/` (16 pruebas) | `flutter test` |
| Manuales en teléfono | Arranque en frío, interrupciones reales, fuente del sistema al 200 %, modo avión, cámara real | Teléfono Android 10 o superior | Guion de las secciones 5, 7 y 8 |
| Aceptación con usuarios | 5 personas del perfil objetivo | Teléfono del equipo | Guion de la sección 9 |

Cada criterio de aceptación (CA) del documento de requerimientos es un caso de
prueba. Las pruebas automatizadas llevan el ID del CA o del RNF en su nombre,
así la matriz de la sección 4 se arma leyendo el resultado real de la ejecución
(`flutter test --reporter json`), no a mano.

## 2. Entorno y comando único (RNF-41)

| Dato | Valor |
|---|---|
| Flutter / Dart | 3.47.9 / 3.13.7 |
| Equipo de ejecución automatizada | Linux x86_64, Intel Xeon 2.30 GHz, 4 núcleos, 15 GB de RAM (entorno de CI en la nube) |
| Comando único | `flutter test` (con cobertura: `flutter test --coverage`) |
| Integración continua | `.github/workflows/pruebas.yml`: `flutter analyze`, `tool/check_quality.py` y `flutter test --coverage` en cada push y PR a `main` |
| Teléfono de referencia | _[Completar: marca, modelo, versión de Android, RAM, cámara]_ |

### Resultado global de la ejecución automatizada (17/11/2026)

| Indicador | Resultado | Meta | Estado |
|---|---|---|---|
| Pruebas ejecutadas | 309 | — | — |
| Aprobadas | 308 | 100 % de las ejecutables | Aprobado |
| Fallidas | 0 | 0 | Aprobado |
| Omitidas | 1: `receipts_accuracy_test.dart` (faltan los 30 recibos y la clave del OCR; ver sección 6) | — | Pendiente |
| Duración | 45 s | — | — |

## 3. Calidad estática, cobertura y seguridad

| RNF | Verificación | Evidencia | Resultado | Estado |
|---|---|---|---|---|
| RNF-24 | Linter `flutter analyze` (reglas `flutter_lints`) en la rama | Salida: `No issues found!` | 0 errores, 0 advertencias, 0 avisos | Aprobado |
| RNF-29 | Ninguna función > 50 líneas ni complejidad > 10 | `python3 tool/check_quality.py` → `0 problemas (máx. 50 líneas, complejidad 10)` | 0 funciones fuera de límite. No se usó el recorte R-C. Es un script aproximado, no un analizador de métricas certificado. | Aprobado |
| RNF-30 | `lib/ui/` no importa `lib/data/` | Mismo script | 0 imports prohibidos | Aprobado |
| RNF-40 | Cobertura ≥ 70 % en la lógica de negocio | `flutter test --coverage`, `coverage/lcov.info` | `lib/modules/` 680/726 líneas = **93.7 %**; `lib/core/` 94/96 = **97.9 %**; ambos juntos 774/822 = **94.2 %**. Todo `lib/`: 2,253/2,366 = 95.2 %. | Aprobado |
| RNF-41 | Un solo comando y pruebas antes de integrar | `flutter test`; workflow de GitHub Actions | 308 aprobadas, 0 fallidas | Aprobado (el bloqueo del PR depende de activar la regla de rama en GitHub) |
| RNF-23 | Sin dependencias con vulnerabilidades críticas conocidas | `flutter pub get` (pub.dev muestra los avisos de seguridad publicados; no mostró ninguno) y `flutter pub outdated` | Dependencias directas: todas en su última versión. Desactualizadas: solo `flutter_lints` 4.0.0 (dev, hay 6.0.0) y transitivas `cross_file`, `material_color_utilities`, `qr`, `lints`, `test_api`, sin avisos de seguridad. La consulta a la base OSV (osv.dev) no se pudo hacer desde el entorno (red bloqueada): **repetir con `osv-scanner --lockfile=pubspec.lock` antes de entregar.** | Aprobado con pendiente |
| RNF-18 | Sin claves en el código ni en el historial | Búsqueda en `git log --all -p` de patrones de claves (`AIza…`, `sk-…`, `ghp_…`, `BEGIN … KEY`, `apiKey: '…'`) y de archivos `.env`, `.json`, `.pem`, `.key` en todo el historial | Solo valores falsos de prueba (`'clave-de-prueba'`, `'k'`). Ningún `.env` versionado; `.env` y `ocr.env.json` en `.gitignore`; `.env.example` sin valores. | Aprobado |
| RNF-20 | `errores.log` sin montos, comercios, notas, rutas ni PIN | `test/integration/performance_test.dart` › "RNF-20": provoca errores reales de guardado y lectura con monto 4,321.99, comercio "Farmacia Secreta" y una nota, y revisa el archivo | La bitácora tiene 2 líneas con fecha, tipo, módulo y clase de la excepción; no contiene el monto, el comercio, la nota ni la ruta de la carpeta. El PIN se revisa con v0.7.0. | Aprobado (PIN: Pendiente v0.7.0) |
| RNF-28 | Ningún error esperado cierra la app; 0 cierres en el flujo principal | Pruebas de errores de almacenamiento, cámara, OCR y exportación devuelven `Failure` con mensaje | 0 excepciones sin controlar en 309 pruebas | Aprobado en pruebas; confirmar en teléfono (sección 7) |

## 4. Matriz de trazabilidad (sección 11 actualizada, RNF-39)

Generada a partir del resultado de la ejecución del 17/11/2026. "Pruebas
automatizadas" cuenta las pruebas cuyo nombre cita alguno de los CA del RF.
H-01 corregido: el criterio de éxito de HU-02 es CA-007.

| RF | Prioridad | HU | Criterios de aceptación (casos) | Pruebas automatizadas | Archivo(s) de prueba | Resultado 17/11/2026 |
|---|---|---|---|---|---|---|
| RF-01 | Must | HU-01 | CA-001 | 4 | unit/movement_service_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-02 | Must | HU-02 | CA-007 | 3 | unit/movement_service_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-03 | Must | HU-01, HU-02 | CA-003, CA-011 | 5 | unit/movement_service_test.dart<br>unit/validators_test.dart | Aprobado |
| RF-04 | Must | HU-01, HU-02 | CA-002, CA-005, CA-008, CA-067 | 7 | integration/scan_flow_test.dart<br>unit/movement_service_test.dart<br>unit/validators_test.dart | Aprobado |
| RF-05 | Must | HU-01, HU-02 | CA-004, CA-009, CA-033, CA-037 | 6 | unit/movement_service_test.dart<br>unit/validators_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-06 | Must | HU-01 | CA-006 | 4 | unit/movement_service_test.dart<br>unit/validators_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-07 | Must | HU-03 | CA-012 a CA-015 | 6 | unit/movement_service_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-08 | Must | HU-04 | CA-016 a CA-020, CA-035 | 15 | unit/movement_service_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-09 | Must | HU-05 | CA-021 a CA-024 | 9 | unit/movement_service_test.dart<br>unit/receipt_service_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-10 | Must | HU-06 | CA-025 a CA-028 | 8 | unit/movement_service_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-11 | Must | HU-07 | CA-029 a CA-031 | 6 | unit/movement_service_test.dart<br>unit/receipt_service_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-12 | Must | HU-08 | CA-032, CA-034, CA-035 | 6 | unit/config_test.dart<br>unit/movement_service_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-13 | Must | HU-09 | CA-036, CA-039 | 4 | unit/config_test.dart<br>unit/movement_service_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-14 | Must | HU-08, HU-09 | CA-010, CA-032, CA-036, CA-038 | 8 | unit/config_test.dart<br>unit/movement_service_test.dart<br>widget/movement_screens_test.dart | Aprobado |
| RF-15 | Must | HU-10 | CA-040, CA-042 | 3 | unit/receipt_service_test.dart<br>widget/receipt_screens_test.dart | Aprobado |
| RF-16 | Must | HU-11 | CA-044 a CA-046 | 2 | unit/receipt_service_test.dart<br>widget/receipt_screens_test.dart | Aprobado |
| RF-17 | Must | HU-12 | CA-047 a CA-049 | 2 | unit/receipt_service_test.dart<br>widget/receipt_screens_test.dart | Aprobado |
| RF-18 | Must | HU-10 | CA-040, CA-041, CA-043 | 9 | unit/receipt_service_test.dart<br>widget/receipt_screens_test.dart | Aprobado |
| RF-19 | Must | HU-13 | CA-050 a CA-052 | 4 | unit/image_store_test.dart<br>unit/receipt_service_test.dart<br>widget/receipt_screens_test.dart | Aprobado |
| RF-20 | Must | HU-14 | CA-053 a CA-055 | 6 | unit/receipt_service_test.dart<br>widget/receipt_screens_test.dart | Aprobado |
| RF-21 | Must | HU-15 | CA-056 a CA-058 | 1 | widget/receipt_screens_test.dart | Aprobado |
| RF-22 | Must | HU-16 | CA-059 a CA-061 | 4 | unit/image_store_test.dart<br>unit/receipt_service_test.dart | Aprobado |
| RF-23 | Must | HU-17 | CA-064, CA-065 | 1 | integration/scan_flow_test.dart | Aprobado parcial: CA-065 pendiente en dispositivo |
| RF-24 | Must | HU-17 | CA-062, CA-063 | 10 | integration/scan_flow_test.dart<br>unit/ocr_service_test.dart<br>unit/receipt_parser_test.dart | Aprobado |
| RF-25 | Must | HU-18 | CA-068, CA-069 | 1 | integration/scan_flow_test.dart | Aprobado |
| RF-26 | Must | HU-18 | CA-066, CA-067 | 2 | integration/scan_flow_test.dart<br>unit/movement_service_test.dart | Aprobado |
| RF-27 | Must | HU-19 | CA-070 | 2 | integration/scan_flow_test.dart<br>unit/receipt_parser_test.dart | Aprobado |
| RF-28 | Must | HU-19 | CA-071 a CA-073 | 3 | integration/scan_flow_test.dart<br>unit/receipt_parser_test.dart | Aprobado |
| RF-29 | Must | HU-20 | CA-074 a CA-076 | 5 | integration/scan_flow_test.dart<br>unit/ocr_service_test.dart<br>unit/receipt_parser_test.dart | Aprobado |
| RF-30 | Must | HU-21 | CA-077 a CA-079, CA-145 | 6 | integration/scan_flow_test.dart<br>unit/ocr_service_test.dart | Aprobado |
| RF-31 | Must | HU-22 | CA-080 a CA-082 | 3 | integration/scan_flow_test.dart<br>unit/ocr_service_test.dart | Aprobado |
| RF-32 | Should | HU-23 | CA-083, CA-084, CA-086 | 5 | unit/movement_filter_test.dart<br>widget/filter_screens_test.dart | Aprobado |
| RF-33 | Should | HU-24 | CA-087 a CA-091 | 5 | unit/movement_filter_test.dart<br>widget/filter_screens_test.dart | Aprobado |
| RF-34 | Should | HU-25 | CA-092 a CA-094 | 5 | unit/movement_filter_test.dart<br>widget/filter_screens_test.dart | Aprobado |
| RF-35 | Should | HU-23 | CA-085 | 1 | widget/filter_screens_test.dart | Aprobado |
| RF-36 | Must | HU-26 | CA-095, CA-097, CA-098 | 6 | unit/annual_summary_calculator_test.dart<br>widget/summary_screens_test.dart | Aprobado |
| RF-37 | Must | HU-27 | CA-099, CA-101, CA-102 | 5 | unit/annual_summary_calculator_test.dart<br>widget/summary_screens_test.dart | Aprobado |
| RF-38 | Must | HU-28 | CA-103 a CA-106 | 4 | unit/annual_summary_calculator_test.dart<br>widget/summary_screens_test.dart | Aprobado |
| RF-39 | Must | HU-27 | CA-100 | 2 | unit/annual_summary_calculator_test.dart<br>widget/summary_screens_test.dart | Aprobado |
| RF-40 | Must | HU-26 | CA-096, CA-098 | 2 | unit/annual_summary_calculator_test.dart<br>widget/summary_screens_test.dart | Aprobado |
| RF-41 | Must | HU-29 | CA-107 a CA-109 | 5 | unit/csv_exporter_test.dart<br>widget/summary_screens_test.dart | Aprobado |
| RF-42 | Must | HU-29 | CA-107, CA-110 | 4 | unit/csv_exporter_test.dart<br>widget/summary_screens_test.dart | Aprobado |
| RF-43 | Must | HU-29 | CA-107 | 3 | unit/csv_exporter_test.dart<br>widget/summary_screens_test.dart | Aprobado |
| RF-44 | Must | HU-30 | CA-111 a CA-113 | 3 | unit/csv_exporter_test.dart<br>widget/summary_screens_test.dart | Aprobado |
| RF-45 | Should | HU-31 | CA-114 a CA-118 | 0 | — | Pendiente (incremento 7, v0.7.0) |
| RF-46 | Should | HU-32 | CA-119 a CA-123 | 0 | — | Pendiente (incremento 7, v0.7.0) |
| RF-47 | Should | HU-33 | CA-124 a CA-127 | 0 | — | Pendiente (incremento 7, v0.7.0) |
| RF-48 | Should | HU-34 | CA-128 a CA-132 | 0 | — | Pendiente (incremento 7, v0.7.0) |
| RF-49 | Should | HU-35 | CA-133 a CA-136 | 0 | — | Pendiente (incremento 7, v0.7.0) |
| RF-50 | Should | HU-36 | CA-137 a CA-140 | 0 | — | Pendiente (incremento 7, v0.7.0) |
| RF-51 | Must | HU-37 | CA-141 a CA-143 | 5 | unit/privacy_settings_test.dart<br>widget/summary_screens_test.dart | Aprobado |
| RF-52 | Should | HU-38 | CA-144 a CA-146 | 3 | integration/offline_test.dart<br>integration/scan_flow_test.dart<br>unit/ocr_service_test.dart | Aprobado |
| RF-53 | Must | HU-39 | CA-052, CA-147 a CA-149 | 4 | unit/image_store_test.dart<br>unit/movement_service_test.dart | Aprobado |
| RF-54 | Must | HU-40 | CA-150 a CA-153 | 6 | unit/formatters_test.dart<br>unit/movement_service_test.dart | Aprobado |

**Resumen:** 54 RF. 47 aprobados con todos sus CA automatizados; 1 aprobado
parcial (RF-23: falta CA-065, el tiempo de respuesta del OCR real, que se mide
con los 30 recibos de la sección 6); 6 pendientes por el incremento 7
(RF-45 a RF-50, *Should*, recortados de la entrega del 23/11/2026). Todos los
RF *Must* (43) están aprobados, salvo la medición de tiempo del OCR real. De los
153 CA, 125 tienen prueba automatizada aprobada, 1 se mide con recibos reales
(CA-065) y 27 son del PIN (CA-114 a CA-140).

## 5. Rendimiento con 2,000 movimientos (RNF-07 a RNF-11)

Medido con `test/integration/performance_test.dart`: base SQLite real en un
archivo con 2,000 movimientos (2/3 egresos, 1/3 ingresos, repartidos en 320
días, con descripción y nota), en el equipo de la sección 2. **Un teléfono de
gama media es más lento que este equipo**; las metas tienen margen de 15× o más,
pero hay que confirmar en el teléfono de referencia.

| RNF | Operación | Meta | Resultado en equipo de CI (17/11/2026) | Estado CI | Resultado en teléfono |
|---|---|---|---|---|---|
| RNF-07 | Arranque en frío hasta la pantalla principal (promedio de 10) | ≤ 3 s | No aplica fuera del teléfono | — | _[Pendiente: medir 10 arranques]_ |
| RNF-08 | Guardar un movimiento y verlo en lista y balance (20 operaciones) | ≤ 1 s | Cubierto funcionalmente por CA-001 y CA-025 | — | _[Pendiente: medir 20 guardados]_ |
| RNF-09 | Cargar la lista de 2,000 | ≤ 2 s | 66 ms | Aprobado | _[Pendiente]_ |
| RNF-09 | Filtro por rango de fechas | ≤ 1 s | 32 ms | Aprobado | _[Pendiente]_ |
| RNF-09 | Filtro por categoría | ≤ 1 s | 7 ms | Aprobado | _[Pendiente]_ |
| RNF-09 | Filtro por tipo | ≤ 1 s | 8 ms | Aprobado | _[Pendiente]_ |
| RNF-09 | Búsqueda por texto | ≤ 1 s | 33 ms | Aprobado | _[Pendiente]_ |
| RNF-10 | Resumen anual | ≤ 3 s | 30 ms | Aprobado | _[Pendiente]_ |
| RNF-11 | Exportar CSV | ≤ 10 s | 2 ms | Aprobado | _[Pendiente]_ |
| RNF-11 | Exportar PDF | ≤ 10 s | 80 ms | Aprobado | _[Pendiente]_ |

Para medir en el teléfono: cargar los datos de prueba (por ejemplo, con un build
de depuración que llame a la misma función `seed` de la prueba) y cronometrar
con la línea de tiempo de Flutter DevTools.

## 6. Precisión y tiempo del OCR con 30 recibos reales (RNF-13, RNF-42)

**Pendiente de ejecutar por el equipo.** Requiere elegir el proveedor (ver
`docs/arquitectura.md`, sección 5.2), tomar las 30 fotos y correr
`test/integration/receipts_accuracy_test.dart` (instrucciones en
`test/fixtures/receipts/README.md`). La prueba automatizada calcula el
porcentaje de totales correctos y de lecturas en ≤ 8 s; la tabla por recibo se
llena a mano revisando cada resultado.

Metas: monto correcto en ≥ 80 % de los recibos legibles (RNF-42); resultado en
≤ 8 s en ≥ 90 % de los intentos con conexión estable (RNF-13).

| # | Comercio | Condición de luz | Legible (sí/no) | Total real | Total leído | Fecha correcta | Comercio correcto | Tiempo (s) |
|---|---|---|---|---|---|---|---|---|
| 01 | | | | | | | | |
| 02 | | | | | | | | |
| 03 | | | | | | | | |
| 04 | | | | | | | | |
| 05 | | | | | | | | |
| 06 | | | | | | | | |
| 07 | | | | | | | | |
| 08 | | | | | | | | |
| 09 | | | | | | | | |
| 10 | | | | | | | | |
| 11 | | | | | | | | |
| 12 | | | | | | | | |
| 13 | | | | | | | | |
| 14 | | | | | | | | |
| 15 | | | | | | | | |
| 16 | | | | | | | | |
| 17 | | | | | | | | |
| 18 | | | | | | | | |
| 19 | | | | | | | | |
| 20 | | | | | | | | |
| 21 | | | | | | | | |
| 22 | | | | | | | | |
| 23 | | | | | | | | |
| 24 | | | | | | | | |
| 25 | | | | | | | | |
| 26 | | | | | | | | |
| 27 | | | | | | | | |
| 28 | | | | | | | | |
| 29 | | | | | | | | |
| 30 | | | | | | | | |

| Indicador | Resultado | Meta | Estado |
|---|---|---|---|
| Proveedor y fecha de la prueba | _[Completar]_ | — | Pendiente |
| % de montos correctos (recibos legibles) | _[Completar]_ | ≥ 80 % | Pendiente |
| % de fechas correctas | _[Completar]_ | Se reporta | Pendiente |
| % de comercios correctos | _[Completar]_ | Se reporta | Pendiente |
| % de lecturas en ≤ 8 s | _[Completar]_ | ≥ 90 % | Pendiente |
| Tamaño de las 30 imágenes ≤ 1.5 MB (RNF-12) | _[Completar]_ | 100 % | Pendiente (automatizado con imágenes sintéticas: CA-043 aprobado) |

## 7. Pruebas de interrupción (RNF-43, RNF-28)

Cada escenario tiene evidencia automatizada (aprobada) y un guion para repetirlo
en el teléfono real.

| # | Escenario | Resultado esperado | Evidencia automatizada (17/11/2026) | Estado automatizado | Guion en teléfono | Resultado en teléfono |
|---|---|---|---|---|---|---|
| 1 | Corte de internet durante la lectura OCR (CA-079, RF-30, CA-077, CA-145) | Aviso claro; la foto se conserva sin corrupción; se puede registrar a mano o reintentar | `scan_flow_test.dart` › "CA-077 / CA-145 / CA-146: sin internet, Reintentar al volver la red"; `ocr_service_test.dart` › "CA-077 / CA-145" y "CA-079: si pasa el tiempo límite termina con timeout"; `offline_test.dart` › "CA-144" con toda la red bloqueada | Aprobado | Escanear un recibo, activar modo avión mientras dice "Leyendo el recibo…"; verificar el aviso, que la foto siga adjunta y que se pueda guardar a mano | _[Pendiente]_ |
| 2 | Cierre forzado durante el guardado de egreso con recibo (RNF-21, CA-031) | Sin movimientos incompletos ni imágenes huérfanas | `receipt_service_test.dart` › "RNF-21 / CA-031", "CA-060 / CA-061: si falla un paso, rollback y sin archivos", "si falla la base, se borra la foto temporal"; `movement_service_test.dart` › "CA-148 / CA-031"; al arrancar, `cleanOrphans()` borra temporales y archivos sin fila | Aprobado | 20 veces: escanear, tocar "Guardar" y cerrar la app desde recientes de inmediato. Reabrir y comparar movimientos con recibo contra archivos en `recibos/` (`adb shell run-as mx.zenorbak.spendy ls files/recibos`) | _[Pendiente: 0 de 20 inconsistencias esperadas]_ |
| 3 | Almacenamiento lleno al guardar movimiento o foto, o al exportar (RF-11, RF-22, RF-44) | Mensaje claro, sin registros ni archivos parciales | `movement_service_test.dart` › "CA-030 error: sin espacio, mensaje no técnico y nada a medias"; `image_store_test.dart` › "CA-059 / CA-060"; `receipt_service_test.dart` › "CA-059"; `csv_exporter_test.dart` › "CA-113: sin espacio da mensaje de espacio y no deja parciales" | Aprobado | Llenar el teléfono (por ejemplo, con un archivo grande de `adb shell fallocate`) y repetir: guardar, tomar foto y exportar | _[Pendiente]_ |
| 4 | Permiso de cámara denegado o cámara ocupada (RF-16, RF-17) | Aviso claro y paso a captura manual conservando datos | `receipt_service_test.dart` › "CA-042", "CA-044", "CA-047 / CA-048"; `receipt_screens_test.dart` › "CA-044 a CA-046: permiso negado explica, ofrece Ajustes y registro manual" y "CA-047 a CA-049: cámara ocupada, Reintentar y datos intactos" | Aprobado | Negar el permiso al primer uso; luego abrir otra app con la cámara (por ejemplo, una videollamada) y tocar "Escanear recibo" | _[Pendiente]_ |

## 8. Accesibilidad, compatibilidad y formato regional

| RNF | Verificación | Evidencia automatizada (17/11/2026) | Estado automatizado | Prueba en teléfono |
|---|---|---|---|---|
| RNF-06 | Áreas táctiles ≥ 44 × 44 pt | `accessibility_sweep_test.dart`: guías `iOSTapTargetGuideline` (44 × 44) y `androidTapTargetGuideline` (48 × 48) en aviso, lista con filtros, formulario y resumen; `movement_screens_test.dart` en detalle y diálogo | Aprobado tras corregir DEF-02 | _[Pendiente: revisión con el escáner de accesibilidad de Android]_ |
| RNF-06 | Contraste de texto ≥ 4.5:1 | `textContrastGuideline` en las mismas pantallas | Aprobado | _[Pendiente]_ |
| RNF-06, RNF-35 | Fuente al 200 % en 5", 6.1" y 6.7" en vertical, sin cortes ni desbordes | `accessibility_sweep_test.dart`: recorre aviso, pantalla principal, formulario, detalle y resumen en 360 × 640, 393 × 852 y 430 × 932 dp con texto al 200 % | Aprobado tras corregir DEF-01 | _[Pendiente: Ajustes › Pantalla › Tamaño de fuente al máximo en el teléfono de referencia y en 2 emuladores (5" y 6.7")]_ |
| RNF-34 | Android 10 (API 29) o superior | `minSdk = 29` en `android/app/build.gradle.kts` | Configurado | _[Pendiente: prueba completa en Android 10 y en la versión más reciente]_ |
| RNF-04, RNF-05 | 100 % de textos y mensajes en español de México, sin códigos ni trazas | Revisión de cadenas de `lib/` (sin textos en inglés ni `toString()` de excepciones en pantallas); mensajes de `ErrorMessages`, `OcrMessages` y `ValidationMessages` | Aprobado | _[Pendiente: recorrido completo]_ |
| RNF-37 | `$1,234.56` y `DD/MM/AAAA` sin importar el idioma del teléfono | `movement_service_test.dart` › "CA-152: idioma y región fijos en es-MX"; `csv_exporter_test.dart` › "CA-110: con el teléfono en inglés (EE. UU.) conserva el formato de México"; `formatters_test.dart` | Aprobado | _[Pendiente: poner el teléfono en inglés (EE. UU.), recorrer pantallas y exportar CSV y PDF]_ |
| RNF-38 | CSV UTF-8 con BOM abre bien en Excel y Google Sheets; PDF estándar | `csv_exporter_test.dart` › "CA-108 / RNF-38", "RNF-38: genera un PDF estándar" | Aprobado | _[Pendiente: abrir los archivos en Excel, Google Sheets y el visor de PDF]_ |
| RNF-14 | Recibos fuera de la galería | `image_store_test.dart` (carpeta privada y `.nomedia`) | Aprobado | _[Pendiente: confirmar que la galería no muestra recibos]_ |

## 9. Pruebas de aceptación con 5 usuarios (RNF-01, RNF-02, RNF-03, RNF-44)

**Pendiente de ejecutar por el equipo (previsto el 22/11/2026).** Perfil
objetivo: personas sin formación contable que quieren llevar sus gastos.

Tareas (cronometrar cada una y anotar si la terminó sin ayuda):

| ID | Tarea | Meta |
|---|---|---|
| T1 | Aceptar el aviso y registrar su primer gasto: $350.00 en Alimentos, pagado en efectivo | RNF-03: al menos 4 de 5 sin ayuda en menos de 2 min. RNF-01: promedio ≤ 20 s desde la pantalla principal (medir en un segundo gasto) |
| T2 | Registrar un ingreso de $15,000.00 | |
| T3 | Corregir el monto del gasto a $400.00 y luego eliminarlo | |
| T4 | Escanear un recibo legible, revisar los datos y guardarlo | RNF-02: ≤ 60 s sin contar la espera del OCR |
| T5 | Encontrar cuánto gastó en "Alimentos" este año y exportar el resumen en PDF | |
| T6 | Decir cuánto le queda del mes | Sin ayuda |

| Usuario | Edad / ocupación | T1 | T2 | T3 | T4 | T5 | T6 |
|---|---|---|---|---|---|---|---|
| U1 | | | | | | | |
| U2 | | | | | | | |
| U3 | | | | | | | |
| U4 | | | | | | | |
| U5 | | | | | | | |

Formato de cada celda: `tiempo · sin ayuda (sí/no) · errores`.

| Hallazgo | Usuarios que lo tuvieron | Severidad | Acción |
|---|---|---|---|
| _[Completar]_ | | | |

| Indicador | Resultado | Meta | Estado |
|---|---|---|---|
| Usuarios que registran su primer gasto sin ayuda en < 2 min | _[x de 5]_ | ≥ 4 de 5 (RNF-03) | Pendiente |
| Promedio para registrar un egreso manual | _[s]_ | ≤ 20 s (RNF-01) | Pendiente |
| Promedio del flujo de escaneo sin la espera del OCR | _[s]_ | ≤ 60 s (RNF-02) | Pendiente |

## 10. Defectos (RNF-45)

### Severidades

| Severidad | Definición |
|---|---|
| Crítico | Pérdida o corrupción de datos, o la app se cierra en el flujo principal. |
| Bloqueante | Impide terminar un flujo principal (registrar, escanear, exportar) o impide instalar o correr la app. |
| Mayor | El flujo se termina, pero con una función importante rota, un texto ilegible o un incumplimiento de un RNF. |
| Menor | Detalle visual, de texto o de documentación que no impide usar la app. |

### Registro de defectos

| ID | Encontrado en | Descripción | Severidad | RNF / RF | Estado | Corrección |
|---|---|---|---|---|---|---|
| DEF-01 | Barrido de accesibilidad, 17/11/2026 | Con la fuente al 200 % en un teléfono de 5" (360 dp), el **Resumen anual** fallaba al dibujarse: el monto de "Ingresos/Egresos del año" y de cada categoría ocupaba todo el ancho del renglón (`ListTile` con `trailing`) y la pantalla quedaba incompleta. | Mayor | RNF-06, RNF-35; RF-36 a RF-40 | Cerrado | `summary_screen.dart`: renglones concepto-monto con `Wrap`; si no caben, el monto baja de renglón. Prueba de regresión: `accessibility_sweep_test.dart`. |
| DEF-02 | Barrido de accesibilidad, 17/11/2026 | El selector **Categoría** de la barra de filtros tenía un área táctil de 24 dp de alto (por `isDense: true`), menor a 44 × 44 pt. | Menor | RNF-06 | Cerrado | `filter_bar.dart`: se quitó `isDense`; ahora mide 48 dp. Prueba: guía `iOSTapTargetGuideline`. |
| DEF-03 | Revisión del README, 17/11/2026 | El repositorio no tenía la carpeta `android/`: `flutter run` no podía instalar la app en un teléfono y el permiso de cámara solo estaba documentado. | Bloqueante | RNF-46, RNF-34; RF-15 | Cerrado | Se generó `android/` (`mx.zenorbak.spendy`, `minSdk 29`) con permisos `CAMERA` e `INTERNET` y `usesCleartextTraffic="false"`. **Falta compilar el APK en una máquina con Android SDK** (no hay SDK en el entorno de CI). |
| DEF-04 | Revisión del README, 17/11/2026 | El README decía que las pruebas corrían en GitHub Actions, pero no existía ningún workflow. | Menor | RNF-41, RNF-46 | Cerrado | Se agregó `.github/workflows/pruebas.yml`. |
| DEF-05 | Revisión de `.gitignore`, 17/11/2026 | La regla `.env.*` ignoraba también `.env.example`, que sí debe versionarse. | Menor | RNF-18, RNF-46 | Cerrado | Excepción `!.env.example`. |

### Estado al cierre

| Indicador | Resultado | Meta | Estado |
|---|---|---|---|
| Críticos o bloqueantes abiertos | 0 | 0 | Aprobado |
| Mayores abiertos | 0 | ≤ 3, con plan de corrección | Aprobado |
| Menores abiertos | 0 | — | — |

Este estado vale para lo probado al 17/11/2026. Las pruebas pendientes de las
secciones 5 a 9 pueden encontrar defectos nuevos: regístralos en esta tabla con
el siguiente ID (DEF-06 en adelante).

## 11. Pendientes para cerrar v1.0.0

| # | Pendiente | Responsable sugerido | Sección |
|---|---|---|---|
| 1 | Elegir proveedor de OCR y correr la prueba de 30 recibos | Equipo | 6 |
| 2 | Compilar el APK y probar en el teléfono de referencia (Android 10 y la más reciente) | Equipo | 5, 7, 8 |
| 3 | Fuente al 200 % y tamaños de pantalla en teléfono o emulador | Julio (Tester) | 8 |
| 4 | Las 4 interrupciones en el teléfono | Julio (Tester) | 7 |
| 5 | Aceptación con 5 usuarios | Equipo | 9 |
| 6 | Repetir la auditoría con `osv-scanner` | Damián | 3 |
| 7 | Activar en GitHub la regla de rama de `main` (PR revisado y pruebas en verde) | Damián | 3 (RNF-25, RNF-41) |
| 8 | Completar la sección del PIN cuando llegue v0.7.0 | Equipo | 4 (RF-45 a RF-50) |
