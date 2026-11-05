# Plan de incrementos · SPENDY

| Dato | Registro |
|---|---|
| Proyecto | SPENDY: app móvil para registrar ingresos, gastos y recibos (Zenorbak 2) |
| Integrantes | Gutiérrez García Julio Augusto (Analista y Tester) · Reynoso Nesme Hugo Damián (Operador de IA y Documentador) |
| Versión del plan | v1.0 · 05/11/2026 |
| Fuente única | Documento de requerimientos de SPENDY, secciones 1 a 13 (docs/SPENDY_especificacion.pdf), y sección 14, plan del incremento 1 (docs/SPENDY_plan_implementacion.pdf) |
| Estado | Propuesta preparada con IA, pendiente de aprobación del equipo |

**Resumen.** Los 54 RF, 51 RNF, 40 HU y 153 CA del documento se reparten en 7 incrementos y un cierre (v1.0.0). Los incrementos 1 a 5 contienen todos los RF Must. La entrega final es el 23/11/2026, así que los incrementos 6 y 7 (solo RF Should) quedan fuera por la regla de recorte (sección 3.3). El incremento 1 está en curso: en main ya está el módulo M-12 (commit b27ef9d).

## 1. Incrementos

| # | Versión | Nombre | RF | HU | CA | Prioridad | Cierre |
|---|---|---|---|---|---|---|---|
| 1 | v0.1.0 | Registrar y consultar movimientos | RF-01 a RF-07, RF-11 a RF-14, RF-53, RF-54 | HU-01 a HU-03, HU-07 a HU-09, HU-39, HU-40 | 35 | Must | 09/11/2026 |
| 2 | v0.2.0 | Editar, eliminar y balance del mes | RF-08 a RF-10 | HU-04 a HU-06 | 14 | Must | 11/11/2026 |
| 3 | v0.3.0 | Recibos con cámara | RF-15 a RF-22 | HU-10 a HU-16 | 22 | Must | 14/11/2026 |
| 4 | v0.4.0 | Lectura OCR con confirmación | RF-23 a RF-31 | HU-17 a HU-22 | 22 | Must | 18/11/2026 |
| 5 | v0.5.0 | Resumen anual, exportación y aviso de privacidad | RF-36 a RF-44, RF-51 | HU-26 a HU-30, HU-37 | 22 | Must | 21/11/2026 |
| — | v1.0.0 | Cierre: pruebas de aceptación, documentación y demo | — | — | — | Must (3.1, funcionalidad 11) | 23/11/2026 (entrega) |
| 6 | — | Búsqueda, filtros y uso sin conexión (recortado) | RF-32 a RF-35, RF-52 | HU-23 a HU-25, HU-38 | 15 | Should | Después del 23/11 |
| 7 | — | Protección de acceso con PIN (recortado) | RF-45 a RF-50 | HU-31 a HU-36 | 27 | Should | Después del 23/11 |

Restricciones: 18 días (del 05/11 al 23/11/2026, unas 2.6 semanas), 2 integrantes, 5 incrementos más el cierre.

**Capacidad.** Según 3.1, los RF Must suman 9.1 semanas-persona; hay unas 5.1 disponibles. Por eso se recortan los incrementos 6 y 7 (3.3) y se proponen los recortes R-A a R-D (sección 2.1). Aun así el calendario es apretado: un incremento cada 2 a 4 días.

Criterios de orden, en este orden: (1) dependencias entre requerimientos; (2) prioridad Must antes que Should (sección 11); (3) mayor riesgo técnico primero (9.1: el OCR); (4) cada incremento termina en algo que se usa de extremo a extremo.

## 2. Fichas por incremento
### Incremento 1 · v0.1.0 · Registrar y consultar movimientos

| Campo | Respuesta del equipo |
|---|---|
| Incremento y versión | Incremento 1 · v0.1.0 |
| Objetivo en una frase | La persona registra ingresos y egresos válidos y los ve en una lista que persiste al cerrar la app y reiniciar el teléfono. |
| RF e HU incluidos | RF-01 a RF-07, RF-11 a RF-14, RF-53, RF-54 (13 RF, prioridad Must). HU-01 a HU-03, HU-07 a HU-09, HU-39, HU-40. RNF verificados aquí: RNF-01, RNF-07, RNF-09, RNF-27, RNF-37. |
| Criterios de aceptación (con sección del documento) | CA-001 a CA-015, CA-029 a CA-039, CA-052, CA-067, CA-147 a CA-153 (35 criterios; sección 8.1, 8.2, 8.3, 8.4, 8.8). |
| Módulos involucrados | M-12 (terminado), M-13, M-11, M-03, M-02, M-01 (formulario y lista) (secciones 12.3 y 12.5). |
| Depende de | Ninguno. Ya está definido y en curso en la sección 14 (Opción A de 14.3, tareas T-01 a T-16). |
| Pruebas mínimas: normal, límite y error | Normal: CA-001, CA-007, CA-012, CA-029, CA-032, CA-036, CA-147, CA-150. Límite: CA-005, CA-006, CA-011, CA-014, CA-015, CA-031, CA-035, CA-039, CA-052, CA-149, CA-153. Error: CA-002 a CA-004, CA-008 a CA-010, CA-013, CA-030, CA-033, CA-034, CA-037, CA-038, CA-067, CA-148, CA-151, CA-152. Ejemplos: normal CA-001: Dado que estoy en el formulario de egreso, cuando capturo monto $350.00, fecha de hoy, categoría "Alimentos" y método "Efectivo" y toco "Guardar", entonces el egreso se guarda, aparece en la lista y el balance del mes se actualiza. Límite CA-005: Dado que capturo un monto de $9,999,999.99, cuando guardo, entonces se acepta; con $10,000,000.00 se rechaza. Error CA-002: Dado que estoy en el formulario, cuando ingreso un monto de 0, negativo, con letras o con más de 2 decimales, entonces el sistema muestra un mensaje junto al campo y no guarda el movimiento. |
| Rama de Git | incremento-1 |
| Fecha de cierre | 09/11/2026 (tag v0.1.0) |
| Decisión del equipo y justificación | Aceptada · Es el incremento definido y aprobado en la sección 14. Con la entrega el 23/11/2026 tiene 4 días para 12 tareas: T-10 y T-11 (pantallas) se hacen en paralelo, como prevé 14.8. Va primero porque todos los demás leen o escriben movimientos (13.8, 14.3) y "registrar" es parte del núcleo que no se recorta (3.3). En main ya están T-01 a T-04 (commit b27ef9d); faltan T-05 a T-16. |

### Incremento 2 · v0.2.0 · Editar, eliminar y balance del mes

| Campo | Respuesta del equipo |
|---|---|
| Incremento y versión | Incremento 2 · v0.2.0 |
| Objetivo en una frase | La persona corrige y elimina movimientos y ve el balance del mes en curso actualizado en la pantalla principal. |
| RF e HU incluidos | RF-08 a RF-10 (3 RF, prioridad Must). HU-04 a HU-06. RNF verificados aquí: RNF-08. |
| Criterios de aceptación (con sección del documento) | CA-016 a CA-028, CA-035 (14 criterios; sección 8.1, 8.2). |
| Módulos involucrados | M-02, M-11, M-01 (secciones 12.3 y 12.5). |
| Depende de | Incremento 1 (movimientos guardados y validadores). Regla de "mes en curso" (AMB-03) definida antes de RF-10. |
| Pruebas mínimas: normal, límite y error | Normal: CA-016, CA-021, CA-025. Límite: CA-019, CA-020, CA-023, CA-024, CA-027, CA-028, CA-035. Error: CA-017, CA-018, CA-022, CA-026. Ejemplos: normal CA-016: Dado que abro un movimiento guardado, cuando cambio el monto y guardo, entonces la lista y el balance reflejan el cambio de inmediato. Límite CA-019: Dado que cambio la categoría o el método de pago de un egreso, cuando guardo, entonces el cambio se refleja en la lista, el detalle y el balance. Error CA-017: Dado que edito un movimiento, cuando pongo un monto inválido o una fecha futura, entonces se aplican las mismas validaciones que al crear y no se guardan los cambios. |
| Rama de Git | incremento-2 |
| Fecha de cierre | 11/11/2026 (tag v0.2.0) |
| Decisión del equipo y justificación | Aceptada · La sección 14.3 deja la Opción B (RF-08, 09 y 10) para el incremento 2. Completa el CRUD de la semana 2-3 del plan 3.2 y es requisito de RF-20 (reemplazar recibo de un egreso existente). |

### Incremento 3 · v0.3.0 · Recibos con cámara

| Campo | Respuesta del equipo |
|---|---|
| Incremento y versión | Incremento 3 · v0.3.0 |
| Objetivo en una frase | La persona toma la foto de un recibo, la vincula a un egreso y la puede ver, ampliar, reemplazar o quitar. |
| RF e HU incluidos | RF-15 a RF-22 (8 RF, prioridad Must). HU-10 a HU-16. RNF verificados aquí: RNF-12, RNF-14, RNF-21, RNF-36. |
| Criterios de aceptación (con sección del documento) | CA-040 a CA-061 (22 criterios; sección 8.3). |
| Módulos involucrados | M-04, M-11 (tabla recibo, imágenes privadas), M-01, M-13 (secciones 12.3 y 12.5). |
| Depende de | Incremento 1 (egresos guardados) e incremento 2 (editar, para RF-20; eliminar, para borrar el recibo en RF-09). Estrategia de guardado atómico (R-04, RNF-21). |
| Pruebas mínimas: normal, límite y error | Normal: CA-040, CA-044, CA-047, CA-050, CA-053, CA-056, CA-059. Límite: CA-043, CA-046, CA-049, CA-052, CA-055, CA-058, CA-061. Error: CA-041, CA-042, CA-045, CA-048, CA-051, CA-054, CA-057, CA-060. Ejemplos: normal CA-040: Dado que toco "Escanear recibo" y concedo el permiso de cámara, cuando tomo la foto, entonces veo una vista previa con "Usar foto" y "Repetir". Límite CA-043: Dado que la foto supera 1.5 MB, cuando toco "Usar foto", entonces la imagen se comprime a 1.5 MB o menos sin perder legibilidad (RNF-12). Error CA-041: Dado que la foto salió borrosa u oscura, cuando toco "Repetir", entonces vuelve la cámara y la foto anterior se descarta. |
| Rama de Git | incremento-3 |
| Fecha de cierre | 14/11/2026 (tag v0.3.0) |
| Decisión del equipo y justificación | Aceptada · La cámara es la entrada del OCR (RF-23 depende de RF-18). Va antes del OCR por dependencia y temprano por riesgo técnico (9.1: el OCR es el mayor riesgo del cronograma). Corresponde a la semana 4-5 del plan 3.2. |

### Incremento 4 · v0.4.0 · Lectura OCR con confirmación

| Campo | Respuesta del equipo |
|---|---|
| Incremento y versión | Incremento 4 · v0.4.0 |
| Objetivo en una frase | La persona escanea un recibo, revisa el comercio, la fecha y el total que se leyeron, los corrige y guarda el egreso. |
| RF e HU incluidos | RF-23 a RF-31 (9 RF, prioridad Must). HU-17 a HU-22. RNF verificados aquí: RNF-02, RNF-13, RNF-16 a RNF-18, RNF-32, RNF-42. |
| Criterios de aceptación (con sección del documento) | CA-062 a CA-082, CA-145 (22 criterios; sección 8.4, 8.8). |
| Módulos involucrados | M-05 (con adaptador de OCR), M-04, M-02, M-01, M-13 (secciones 12.3 y 12.5). |
| Depende de | Incremento 3 (foto aceptada). Proveedor de OCR y manejo de su clave decididos antes de empezar (9.2, TEC-01, TEC-02). |
| Pruebas mínimas: normal, límite y error | Normal: CA-062, CA-066, CA-070, CA-074, CA-077, CA-080. Límite: CA-065, CA-069, CA-073, CA-076, CA-079, CA-082. Error: CA-063, CA-064, CA-067, CA-068, CA-071, CA-072, CA-075, CA-078, CA-081, CA-145. Ejemplos: normal CA-062: Dado que acepté la foto de un recibo legible y hay conexión, cuando el OCR termina, entonces el formulario aparece prellenado con comercio, fecha y total. Límite CA-065: Dado que el recibo es legible y hay conexión estable, cuando se envía al OCR, entonces el resultado llega en 8 s o menos en al menos el 90 % de los casos (RNF-13). Error CA-063: Dado que el OCR no extrajo un campo (por ejemplo, el comercio), cuando se abre el formulario, entonces ese campo queda vacío y resaltado. |
| Rama de Git | incremento-4 |
| Fecha de cierre | 18/11/2026 (tag v0.4.0) |
| Decisión del equipo y justificación | Aceptada · Es el requerimiento de mayor riesgo técnico (9.1) y parte del núcleo que no se recorta (3.3: "escanear con confirmación"). Se pone lo más pronto que permiten sus dependencias. Si el OCR falla, se mantiene la captura manual con la foto adjunta (mitigación de 9.1). El proveedor de OCR se decide a más tardar el 11/11 para no frenar este incremento. |

### Incremento 5 · v0.5.0 · Resumen anual, exportación y aviso de privacidad

| Campo | Respuesta del equipo |
|---|---|
| Incremento y versión | Incremento 5 · v0.5.0 |
| Objetivo en una frase | La persona consulta el resumen de un año, lo exporta en CSV o PDF, y al primer inicio acepta el aviso de privacidad. |
| RF e HU incluidos | RF-36 a RF-44, RF-51 (10 RF, prioridad Must). HU-26 a HU-30, HU-37. RNF verificados aquí: RNF-10, RNF-11, RNF-33, RNF-38, RNF-51. |
| Criterios de aceptación (con sección del documento) | CA-095 a CA-113, CA-141 a CA-143 (22 criterios; sección 8.6, 8.8). |
| Módulos involucrados | M-07, M-08, M-10, M-11, M-01 (secciones 12.3 y 12.5). |
| Depende de | Incremento 1 (movimientos y categorías). RF-51 depende del incremento 4, porque el aviso debe nombrar al proveedor de OCR (9.2, RNF-17). |
| Pruebas mínimas: normal, límite y error | Normal: CA-095, CA-099, CA-103, CA-107, CA-111, CA-141. Límite: CA-097, CA-098, CA-101, CA-102, CA-105, CA-106, CA-109, CA-110, CA-113, CA-143. Error: CA-096, CA-100, CA-104, CA-108, CA-112, CA-142. Ejemplos: normal CA-095: Dado que tengo movimientos de 2025 y 2026, cuando abro el resumen, entonces aparece 2026 por defecto y puedo elegir 2025. Límite CA-097: Dado que solo tengo movimientos del año en curso, cuando abro el selector, entonces solo aparece ese año. Error CA-096: Dado que el año seleccionado no tiene movimientos, cuando lo consulto, entonces aparece un mensaje informativo en lugar de un resumen vacío. |
| Rama de Git | incremento-5 |
| Fecha de cierre | 21/11/2026 (tag v0.5.0) |
| Decisión del equipo y justificación | Aceptada · Cierra el núcleo que no se recorta (3.3: "exportar el resumen"). El cálculo del resumen (M-07) solo depende del incremento 1, así que la otra persona puede empezarlo desde el 12/11 en una rama de tarea, mientras se hace el OCR. Con RF-51 aquí, los incrementos 1 a 5 contienen todos los RF Must y los incrementos 6 y 7 solo RF Should, que son los primeros en recortarse. |

### Incremento 6 · v0.6.0 · Búsqueda, filtros y uso sin conexión (recortado de esta entrega)

| Campo | Respuesta del equipo |
|---|---|
| Incremento y versión | Incremento 6 · v0.6.0 |
| Objetivo en una frase | La persona filtra y busca sus movimientos, ve cuántos son y cuánto suman, y usa toda la app en modo avión excepto el OCR. |
| RF e HU incluidos | RF-32 a RF-35, RF-52 (5 RF, prioridad Should). HU-23 a HU-25, HU-38. RNF verificados aquí: ninguno (RNF-09 y RNF-43 pasaron al incremento 1 y al cierre). |
| Criterios de aceptación (con sección del documento) | CA-083 a CA-094, CA-144 a CA-146 (15 criterios; sección 8.5, 8.8). |
| Módulos involucrados | M-06, M-11, M-01 (secciones 12.3 y 12.5). |
| Depende de | Incremento 1 (lista, RF-07). RF-52 se verifica con todas las funciones construidas (incrementos 1 a 5); regla de OCR sin conexión (ALC-08). |
| Pruebas mínimas: normal, límite y error | Normal: CA-083, CA-087, CA-092, CA-144. Límite: CA-086, CA-090, CA-091, CA-094, CA-146. Error: CA-084, CA-085, CA-088, CA-089, CA-093, CA-145. Ejemplos: normal CA-083: Dado que tengo movimientos de varios meses, cuando filtro por rango de fechas y categoría "Transporte", entonces la lista muestra solo los que cumplen los dos filtros a la vez. Límite CA-086: Dado que hay 2,000 movimientos, cuando aplico un filtro, entonces el resultado aparece en 1 s o menos (RNF-09). Error CA-084: Dado que pongo una fecha final anterior a la inicial, cuando aplico el filtro, entonces el sistema avisa que el rango no es válido y no aplica el filtro. |
| Rama de Git | incremento-6 |
| Fecha de cierre | Recortado: después del 23/11/2026 |
| Decisión del equipo y justificación | Modificada: fuera de la entrega del 23/11/2026 · Recortado de la entrega del 23/11/2026 por la regla de recorte (3.3): son RF Should (sección 11) y no caben en el tiempo disponible. RF-52 va aquí porque su prueba (CA-144) recorre registrar, editar, filtrar y exportar en modo avión, y eso solo existe al terminar el incremento 5. |

### Incremento 7 · v0.7.0 · Protección de acceso con PIN (recortado de esta entrega)

| Campo | Respuesta del equipo |
|---|---|
| Incremento y versión | Incremento 7 · v0.7.0 |
| Objetivo en una frase | La persona protege la app con un PIN de 6 dígitos o biometría, y puede cambiarlo, desactivarlo o restablecer la app si lo olvida. |
| RF e HU incluidos | RF-45 a RF-50 (6 RF, prioridad Should). HU-31 a HU-36. RNF verificados aquí: RNF-15, RNF-19, RNF-22. |
| Criterios de aceptación (con sección del documento) | CA-114 a CA-140 (27 criterios; sección 8.7). |
| Módulos involucrados | M-09, M-11 (almacén seguro), M-01 (secciones 12.3 y 12.5). |
| Depende de | Incremento 1. RF-50 borra todos los datos, incluidos los recibos (incremento 3). Decisión D-02 (PIN opcional u obligatorio). |
| Pruebas mínimas: normal, límite y error | Normal: CA-114, CA-119, CA-124, CA-128, CA-133, CA-137. Límite: CA-117, CA-118, CA-122, CA-123, CA-127, CA-131, CA-132, CA-136, CA-139, CA-140. Error: CA-115, CA-116, CA-120, CA-121, CA-125, CA-126, CA-129, CA-130, CA-134, CA-135, CA-138. Ejemplos: normal CA-114: Dado que estoy en Configuración, cuando capturo un PIN de 6 dígitos y lo repito igual, entonces el PIN se activa. Límite CA-117: Dado que cierro la app a mitad de la activación, cuando la reabro, entonces el PIN no queda activado a medias. Error CA-115: Dado que el PIN tiene menos o más de 6 dígitos o contiene letras, cuando intento activarlo, entonces el sistema lo rechaza y explica el formato. |
| Rama de Git | incremento-7 |
| Fecha de cierre | Recortado: después del 23/11/2026 |
| Decisión del equipo y justificación | Modificada: fuera de la entrega del 23/11/2026 · Recortado de la entrega del 23/11/2026 por la regla de recorte (3.3): es Should (sección 11), el módulo más grande para su valor (GRA-04, gravedad Alta) y no bloquea a ningún otro RF. |

### Cierre · v1.0.0

Corresponde a la funcionalidad 11 de la sección 3.1 (pruebas, documentación y demo) y a la semana 8 del plan 3.2. No agrega RF: verifica la app completa.

| Campo | Respuesta del equipo |
|---|---|
| RNF verificados | RNF-03, RNF-06, RNF-23, RNF-34, RNF-35, RNF-43, RNF-44, RNF-45, RNF-48, RNF-49, RNF-50 |
| Qué se entrega | Pruebas de aceptación con 5 personas (RNF-03, RNF-44), revisión de accesibilidad y tamaños de pantalla (RNF-06, RNF-35), auditoría de dependencias (RNF-23), plataforma confirmada (RNF-34), lista de defectos (RNF-45), documento de arquitectura (RNF-48), manual de usuario (RNF-49) y reporte de pruebas (RNF-50) |
| Depende de | Incrementos 1 a 5 |
| Fecha | 22 y 23/11/2026: prueba con usuarios el 22/11 y entrega el 23/11 |

### 2.1 Recortes adicionales propuestos

Necesitan el visto bueno del profesor, porque cambian RF Must o su forma de prueba. Todos salen de las recomendaciones del propio documento.

| ID | Requerimientos | Respaldo en el documento | Propuesta | Efecto |
|---|---|---|---|---|
| R-A | RF-20, HU-14 | ALC-03 (9.3) | Dejar solo agregar el recibo al crear el egreso; reemplazar y quitar quedan para después. | Ahorra 3 CA (CA-053 a CA-055) y pantallas del incremento 3. |
| R-B | RF-23 a RF-31 | GRA-05 (9.3) | Construir primero el flujo exitoso (RF-23 a RF-26) y la salida manual (RF-29 a RF-31); RF-27 y RF-28 al final del incremento 4. | Asegura un OCR que funciona aunque falten casos de error. |
| R-C | RNF-29, parte de RNF-36 | 9.2 | Son los primeros RNF que el documento permite recortar. | Menos revisión de complejidad y menos dispositivos de prueba. |
| R-D | RNF-44, RNF-03 | 3.2 (semana 8) y tiempo | Hacer la prueba con usuarios el 22/11, con las 5 personas en una sola sesión. | Cabe en el cierre sin mover fechas. |

### RNF transversales

Se verifican en cada incremento, como parte de su definición de terminado: RNF-04, RNF-05, RNF-20, RNF-24, RNF-25, RNF-26, RNF-28, RNF-29, RNF-30, RNF-31, RNF-39, RNF-40, RNF-41, RNF-46, RNF-47.

## 3. Inventario de requerimientos

Estado al 05/11/2026. "En curso" significa que la parte de validación ya está en main (módulo M-12, commit b27ef9d), pero el RF todavía no funciona de extremo a extremo. Ningún RF está "Implementado" todavía.

### 3.1 Requerimientos funcionales (54)

| ID | Descripción breve | Tipo | Prioridad | Depende de | Sección | Estado |
|---|---|---|---|---|---|---|
| RF-01 | Crear un egreso con monto, fecha, categoría y método de pago obligatorios. | Funcional | Must | Ninguna | 5.1 | Pendiente |
| RF-02 | Crear un ingreso con monto, fecha y categoría obligatorios. | Funcional | Must | Ninguna | 5.1 | Pendiente |
| RF-03 | Fecha actual por defecto; no permitir fechas futuras. | Funcional | Must | RF-01, RF-02 (5.1: aplica a la fecha de ambos formularios) | 5.1 | En curso (validación en M-12) |
| RF-04 | Validar monto mayor a 0, 2 decimales y máximo 9,999,999.99. | Funcional | Must | RF-01, RF-02 (5.1) | 5.1 | En curso (validación en M-12) |
| RF-05 | Indicar el campo obligatorio faltante y conservar lo capturado. | Funcional | Must | RF-01, RF-02 (5.1) | 5.1 | En curso (validación en M-12) |
| RF-06 | Contador de caracteres en nota y descripción; no exceder el límite. | Funcional | Must | RF-01, RF-02 (5.1: nota y descripción) | 5.1 | En curso (validación en M-12) |
| RF-07 | Lista por fecha descendente que distingue ingresos y egresos. | Funcional | Must | RF-01, RF-02 (5.1: lista de movimientos guardados) | 5.1 | Pendiente |
| RF-08 | Editar un movimiento con las mismas validaciones que al crearlo. | Funcional | Must | RF-01 a RF-06 (5.1: "aplicando las mismas validaciones"); RF-07, RF-10 (5.1) | 5.1 | Pendiente |
| RF-09 | Confirmar antes de eliminar; borrar también el recibo asociado. | Funcional | Must | RF-07 (5.1); RF-19 (5.1 y 5.3: "eliminará también el recibo asociado") | 5.1 | Pendiente |
| RF-10 | Balance del mes en curso en la pantalla principal. | Funcional | Must | RF-01, RF-02, RF-08, RF-09 (5.1: "al crear, editar o eliminar") | 5.1 | Pendiente |
| RF-11 | Error de almacenamiento sin perder lo capturado en el formulario. | Funcional | Must | RF-01, RF-02 (5.1) | 5.1 | Pendiente |
| RF-12 | Categorías fijas de egreso (6 categorías generales). | Funcional | Must | Ninguna | 5.2 | En curso (validación en M-12) |
| RF-13 | Categorías fijas de ingreso: Sueldos y salarios, Otros ingresos. | Funcional | Must | Ninguna | 5.2 | En curso (validación en M-12) |
| RF-14 | Solo permitir categorías del tipo de movimiento elegido. | Funcional | Must | RF-12, RF-13 (5.2) | 5.2 | En curso (validación en M-12) |
| RF-15 | Pedir permiso de cámara la primera vez que se escanea. | Funcional | Must | Ninguna | 5.3 | Pendiente |
| RF-16 | Si se niega el permiso, explicar y ofrecer registro manual y ajustes. | Funcional | Must | RF-15 (5.3) | 5.3 | Pendiente |
| RF-17 | Si la cámara falla, mostrar error y ofrecer registro manual. | Funcional | Must | RF-15 (5.3) | 5.3 | Pendiente |
| RF-18 | Vista previa de la foto con "Usar foto" y "Repetir". | Funcional | Must | RF-15 (5.3) | 5.3 | Pendiente |
| RF-19 | Guardar la imagen localmente, vincularla al egreso y poder ampliarla. | Funcional | Must | RF-18, RF-01 (5.3: "vinculará al egreso") | 5.3 | Pendiente |
| RF-20 | Agregar, reemplazar o quitar el recibo de un egreso, con confirmación. | Funcional | Must | RF-19, RF-08 (5.3: recibo de un egreso existente) | 5.3 | Pendiente |
| RF-21 | Preguntar si se descarta al salir sin guardar; borrar imagen temporal. | Funcional | Must | RF-18 (5.3) | 5.3 | Pendiente |
| RF-22 | Sin espacio para la imagen: error y ningún movimiento incompleto. | Funcional | Must | RF-19 (5.3) | 5.3 | Pendiente |
| RF-23 | Enviar la foto al OCR con indicador de progreso y opción de cancelar. | Funcional | Must | RF-18 (5.4: "tras aceptar la foto") | 5.4 | Pendiente |
| RF-24 | Prellenar comercio, fecha y total; resaltar los campos no extraídos. | Funcional | Must | RF-23, RF-01 (5.4: formulario de egreso) | 5.4 | Pendiente |
| RF-25 | Mostrar siempre la revisión; no guardar hasta tocar "Guardar". | Funcional | Must | RF-24 (5.4) | 5.4 | Pendiente |
| RF-26 | Guardar los valores confirmados por el usuario, no los extraídos. | Funcional | Must | RF-25, RF-03, RF-04 (5.4; 9.3 DUP-01) | 5.4 | Pendiente |
| RF-27 | Fecha extraída inválida o futura: dejar la fecha actual con aviso. | Funcional | Must | RF-24, RF-03 (5.4) | 5.4 | Pendiente |
| RF-28 | Total extraído inválido: dejar el campo vacío y resaltado. | Funcional | Must | RF-24, RF-04 (5.4) | 5.4 | Pendiente |
| RF-29 | Imagen ilegible: ofrecer repetir foto o registro manual con la foto. | Funcional | Must | RF-23 (5.4) | 5.4 | Pendiente |
| RF-30 | Sin conexión, error o más de 10 s: reintentar o registro manual. | Funcional | Must | RF-23 (5.4) | 5.4 | Pendiente |
| RF-31 | Cancelar el OCR y pasar al formulario manual con la foto. | Funcional | Must | RF-23 (5.4) | 5.4 | Pendiente |
| RF-32 | Filtros combinables por rango de fechas, categoría y tipo. | Funcional | Should | RF-07 (5.5: "filtrar la lista de movimientos") | 5.5 | Recortado (3.3) |
| RF-33 | Búsqueda por texto en descripción y nota. | Funcional | Should | RF-07 (5.5) | 5.5 | Recortado (3.3) |
| RF-34 | Mostrar número de resultados y suma de montos filtrados. | Funcional | Should | RF-32, RF-33 (5.5) | 5.5 | Recortado (3.3) |
| RF-35 | Sin resultados: mensaje y opción "Limpiar filtros". | Funcional | Should | RF-32 (5.5) | 5.5 | Recortado (3.3) |
| RF-36 | Seleccionar año: actual por defecto, solo años con movimientos. | Funcional | Must | RF-01, RF-02 (5.6) | 5.6 | Pendiente |
| RF-37 | Totales anuales de ingresos, egresos y diferencia. | Funcional | Must | RF-36 (5.6) | 5.6 | Pendiente |
| RF-38 | Total de gastos por categoría del año seleccionado. | Funcional | Must | RF-36, RF-12 (5.6) | 5.6 | Pendiente |
| RF-39 | Los totales del resumen coinciden con la suma de movimientos. | Funcional | Must | RF-37, RF-38 (5.6) | 5.6 | Pendiente |
| RF-40 | Año sin movimientos: mensaje informativo en lugar de resumen vacío. | Funcional | Must | RF-36 (5.6) | 5.6 | Pendiente |
| RF-41 | Exportar el resumen del año en CSV o PDF. | Funcional | Must | RF-37, RF-38 (5.6) | 5.6 | Pendiente |
| RF-42 | El archivo incluye año, fecha de generación, totales y desglose. | Funcional | Must | RF-41 (5.6) | 5.6 | Pendiente |
| RF-43 | Nombre spendy_resumen_AAAA y entrega por el menú compartir del sistema. | Funcional | Must | RF-41 (5.6) | 5.6 | Pendiente |
| RF-44 | Si la exportación falla: mensaje, sin archivos parciales, permitir reintentar. | Funcional | Must | RF-41 (5.6) | 5.6 | Pendiente |
| RF-45 | Activar PIN de 6 dígitos capturado dos veces desde Configuración. | Funcional | Should | Ninguna | 5.7 | Recortado (3.3) |
| RF-46 | Pedir PIN al abrir y al volver tras más de 1 minuto. | Funcional | Should | RF-45 (5.7) | 5.7 | Recortado (3.3) |
| RF-47 | Biometría como alternativa al PIN, con PIN de respaldo. | Funcional | Should | RF-45, RF-46 (5.7) | 5.7 | Recortado (3.3) |
| RF-48 | PIN incorrecto: intentos restantes; bloqueo de 30 s tras 5 fallos. | Funcional | Should | RF-46 (5.7) | 5.7 | Recortado (3.3) |
| RF-49 | Cambiar o desactivar el PIN solo con el PIN actual. | Funcional | Should | RF-45 (5.7) | 5.7 | Recortado (3.3) |
| RF-50 | PIN olvidado: restablecer la app borrando datos, con doble confirmación. | Funcional | Should | RF-45 (5.7) | 5.7 | Recortado (3.3) |
| RF-51 | Aviso de privacidad obligatorio en el primer inicio. | Funcional | Must | Contenido del aviso depende del proveedor de OCR (9.2; RNF-17, RNF-51) | 5.8 | Pendiente |
| RF-52 | Todo funciona sin conexión, excepto la lectura OCR. | Funcional | Should | Todas las funciones (5.8: "excepto la lectura OCR") | 5.8 | Recortado (3.3) |
| RF-53 | Datos e imágenes persisten al cerrar la app y reiniciar el dispositivo. | Funcional | Must | RF-01, RF-02, RF-19 (5.8: datos e imágenes) | 5.8 | Pendiente |
| RF-54 | Montos $1,234.56 y fechas DD/MM/AAAA en español de México. | Funcional | Must | Ninguna (5.8) | 5.8 | En curso (validación en M-12) |

### 3.2 Requerimientos no funcionales (51)

El documento no asigna prioridad a los RNF; la sección 9.2 solo indica cuáles recortar al final (RNF-14 a RNF-17, RNF-21, RNF-39) y cuáles primero (RNF-29, parte de RNF-36).

| ID | Descripción breve | Tipo | Prioridad | Depende de | Sección | Estado |
|---|---|---|---|---|---|---|
| RNF-01 | Registrar un egreso manual en 20 s o menos. | No funcional · Usabilidad | No indicada | RF-01 | 6.1 | Pendiente |
| RNF-02 | Flujo de escaneo hasta guardar en 60 s o menos, sin espera del OCR. | No funcional · Usabilidad | No indicada | RF-15 a RF-26 | 6.1 | Pendiente |
| RNF-03 | 4 de 5 usuarios nuevos registran su primer gasto sin ayuda en menos de 2 min. | No funcional · Usabilidad | No indicada | Ninguna | 6.1 | Pendiente |
| RNF-04 | Todos los textos en español de México con terminología uniforme. | No funcional · Usabilidad | No indicada | Ninguna | 6.1 | Pendiente |
| RNF-05 | Mensajes de error con causa no técnica y acción siguiente. | No funcional · Usabilidad | No indicada | Ninguna | 6.1 | Pendiente |
| RNF-06 | Contraste 4.5:1, áreas táctiles de 44 pt y texto al 200 %. | No funcional · Usabilidad | No indicada | Ninguna | 6.1 | Pendiente |
| RNF-07 | Arranque en frío en 3 s o menos. | No funcional · Rendimiento | No indicada | Ninguna | 6.2 | Pendiente |
| RNF-08 | Guardar y ver el movimiento en lista y balance en 1 s o menos. | No funcional · Rendimiento | No indicada | RF-10 (balance) | 6.2 | Pendiente |
| RNF-09 | Con 2,000 movimientos: lista en 2 s; filtros y búsqueda en 1 s. | No funcional · Rendimiento | No indicada | RF-07, RF-32, RF-33 | 6.2 | Pendiente |
| RNF-10 | Con 2,000 movimientos: resumen anual en 3 s o menos. | No funcional · Rendimiento | No indicada | RF-37, RF-38 | 6.2 | Pendiente |
| RNF-11 | Exportar CSV o PDF con 2,000 movimientos en 10 s o menos. | No funcional · Rendimiento | No indicada | RF-41 | 6.2 | Pendiente |
| RNF-12 | Imágenes comprimidas a 1.5 MB o menos, legibles. | No funcional · Rendimiento | No indicada | RF-19 | 6.2 | Pendiente |
| RNF-13 | OCR responde en 8 s o menos en al menos 90 % de intentos. | No funcional · Rendimiento | No indicada | RF-23 | 6.2 | Pendiente |
| RNF-14 | Datos e imágenes en almacenamiento privado; recibos fuera de la galería. | No funcional · Seguridad | No indicada | Ninguna | 6.3 | Pendiente |
| RNF-15 | PIN guardado como hash con sal en el almacén seguro. | No funcional · Seguridad | No indicada | RF-45 | 6.3 | Recortado (3.3) |
| RNF-16 | Comunicación con el OCR solo por HTTPS (TLS 1.2 o superior). | No funcional · Seguridad | No indicada | RF-23 | 6.3 | Pendiente |
| RNF-17 | Al OCR solo se envía la imagen; el aviso informa del tercero. | No funcional · Seguridad | No indicada | RF-23, RF-51 | 6.3 | Pendiente |
| RNF-18 | Claves del OCR fuera del código y del repositorio. | No funcional · Seguridad | No indicada | RF-23 | 6.3 | Pendiente |
| RNF-19 | Con PIN activo, ocultar contenido en apps recientes. | No funcional · Seguridad | No indicada | RF-45 | 6.3 | Recortado (3.3) |
| RNF-20 | Bitácoras sin montos, comercios, notas, imágenes ni PIN. | No funcional · Seguridad | No indicada | Ninguna | 6.3 | Pendiente |
| RNF-21 | Guardado atómico de egreso con recibo. | No funcional · Seguridad | No indicada | RF-19 | 6.3 | Pendiente |
| RNF-22 | Intentos fallidos y bloqueo del PIN persisten al reiniciar. | No funcional · Seguridad | No indicada | RF-48 | 6.3 | Recortado (3.3) |
| RNF-23 | Sin dependencias con vulnerabilidades críticas al entregar. | No funcional · Seguridad | No indicada | Ninguna | 6.3 | Pendiente |
| RNF-24 | Linter y formateador configurados; 0 errores en la rama principal. | No funcional · Mantenibilidad | No indicada | Ninguna | 6.4 | En curso |
| RNF-25 | Cambios a la rama principal por pull request revisado. | No funcional · Mantenibilidad | No indicada | Ninguna | 6.4 | Pendiente |
| RNF-26 | Categorías y límites en un único lugar de configuración. | No funcional · Mantenibilidad | No indicada | Ninguna | 6.4 | En curso |
| RNF-27 | Esquema de datos versionado con migraciones sin pérdida de datos. | No funcional · Mantenibilidad | No indicada | Ninguna | 6.4 | Pendiente |
| RNF-28 | Errores controlados en bitácora local; 0 cierres inesperados. | No funcional · Mantenibilidad | No indicada | Ninguna | 6.4 | Pendiente |
| RNF-29 | Complejidad ciclomática de 10 o menos y funciones de 50 líneas o menos. | No funcional · Mantenibilidad | No indicada | Ninguna | 6.4 | Pendiente |
| RNF-30 | Capas presentación, lógica y datos; pantallas sin acceso directo a la base. | No funcional · Modularidad | No indicada | Ninguna | 6.5 | Pendiente |
| RNF-31 | Módulos separados con interfaz definida. | No funcional · Modularidad | No indicada | Ninguna | 6.5 | Pendiente |
| RNF-32 | OCR consumido mediante un adaptador reemplazable. | No funcional · Modularidad | No indicada | RF-23 a RF-31 | 6.5 | Pendiente |
| RNF-33 | Resumen independiente de la interfaz; cada formato de exportación separado. | No funcional · Modularidad | No indicada | RF-37, RF-41 | 6.5 | Pendiente |
| RNF-34 | Android 10+ e iOS 15+ (ajustar a la plataforma elegida). | No funcional · Compatibilidad | No indicada | Ninguna | 6.6 | Pendiente |
| RNF-35 | Teléfonos de 5" a 6.7" en vertical sin elementos cortados. | No funcional · Compatibilidad | No indicada | Ninguna | 6.6 | Pendiente |
| RNF-36 | Cámara trasera de 8 MP y dispositivos de gama media. | No funcional · Compatibilidad | No indicada | Ninguna | 6.6 | Pendiente |
| RNF-37 | Formatos de México sin importar idioma o región del dispositivo. | No funcional · Compatibilidad | No indicada | Ninguna | 6.6 | En curso |
| RNF-38 | CSV en UTF-8 con BOM legible en Excel y Sheets; PDF estándar. | No funcional · Compatibilidad | No indicada | RF-41 | 6.6 | Pendiente |
| RNF-39 | Cada RF con al menos un caso de prueba trazable. | No funcional · Pruebas | No indicada | Ninguna | 6.7 | Pendiente |
| RNF-40 | Cobertura de pruebas unitarias de 70 % o más en la lógica. | No funcional · Pruebas | No indicada | Ninguna | 6.7 | En curso |
| RNF-41 | Pruebas con un solo comando; deben pasar antes de integrar. | No funcional · Pruebas | No indicada | Ninguna | 6.7 | Pendiente |
| RNF-42 | Precisión del OCR medida con 30 recibos; 80 % o más en monto. | No funcional · Pruebas | No indicada | RF-24 | 6.7 | Pendiente |
| RNF-43 | Pruebas de interrupción sin pérdida ni corrupción de datos. | No funcional · Pruebas | No indicada | RF-11, 17, 18, 23, 31, 52 (texto de RNF-43) | 6.7 | Pendiente |
| RNF-44 | Pruebas de aceptación con al menos 5 personas. | No funcional · Pruebas | No indicada | Ninguna | 6.7 | Pendiente |
| RNF-45 | Entrega con 0 defectos críticos y máximo 3 mayores con plan. | No funcional · Pruebas | No indicada | Ninguna | 6.7 | Pendiente |
| RNF-46 | README que permite levantar el proyecto en 30 min o menos. | No funcional · Documentación | No indicada | Ninguna | 6.8 | Pendiente |
| RNF-47 | Documento de requerimientos versionado con registro de cambios. | No funcional · Documentación | No indicada | Ninguna | 6.8 | Pendiente |
| RNF-48 | Documento de arquitectura con módulos, datos y justificación del OCR. | No funcional · Documentación | No indicada | Ninguna | 6.8 | Pendiente |
| RNF-49 | Manual de usuario de máximo 10 páginas. | No funcional · Documentación | No indicada | Ninguna | 6.8 | Pendiente |
| RNF-50 | Plan de pruebas y reporte de resultados. | No funcional · Documentación | No indicada | Ninguna | 6.8 | Pendiente |
| RNF-51 | Aviso de privacidad claro mostrado en el primer inicio. | No funcional · Documentación | No indicada | RF-51 | 6.8 | Pendiente |

## 4. Ambigüedades y decisiones

| ID | Requerimiento | Ambigüedad detectada | Resolución del equipo |
|---|---|---|---|
| H-01 (14.2) | CA-007 | En la sección 8.1 el criterio de éxito de HU-02 aparece como "CA-00,". La matriz (11) y 12.5 usan CA-007. | Se toma como CA-007. Corregir el ID en 8.1 del documento. |
| ALC-01 / H-03 (9.3, 14.2) | RNF-34 | El alcance elige una sola plataforma, pero RNF-34 pide Android e iOS. | Parcial: el equipo eligió Flutter (código en main). Falta confirmar en qué plataforma se prueba (D-01) y ajustar RNF-34. Antes del cierre v1.0.0. |
| AMB-06 / D-03 | RF-04, RF-54, CA-151 | No se define qué pasa con un monto con coma decimal (12,5). | Resuelta: solo punto decimal; la coma se rechaza con mensaje. Implementado en lib/core/validators.dart (b27ef9d). |
| AMB-01 / D-04 | RF-03, RNF-05 | "El mensaje de error correspondiente" no está definido. | Resuelta: catálogo único ValidationMessages en lib/core/validators.dart (b27ef9d). |
| AMB-03 / R-03 | RF-10, CA-028 | "Mes en curso" no precisa mes calendario ni zona horaria. | Pendiente. Propuesta del documento (9.3): mes calendario en la zona horaria del dispositivo. Resolver antes del incremento 2. |
| TEC-01, TEC-02 (9.3); 9.2 | RF-23 a RF-31, RNF-16 a RNF-18 | No está elegido el proveedor de OCR ni cómo proteger su clave sin servidor propio. | Pendiente. Resolver antes del incremento 4. Afecta también el texto del aviso (RF-51). |
| ALC-08 (9.3) | RF-52 | Se menciona OCR "en cola" sin conexión, pero ningún RF lo define. | Pendiente. Propuesta: no hay cola; sin conexión aplica RF-30 (reintentar o registro manual). Resolver antes del incremento 6. |
| H-02 / D-02 (14.2, 14.9) | RF-45 a RF-50 | No está claro si el PIN es opcional u obligatorio. | Pendiente. El documento lo define como opcional ("permitirá activar", Should). Resolver antes del incremento 7. |
| GRA-04 (9.3) | RF-45 a RF-50 | El módulo de protección de acceso es grande para su valor (gravedad Alta). | Se coloca al final (incremento 7) y es el primero que se recorta según 3.3. |
| P-01 (nueva) | Incremento 1 | La guía pide marcar main con v0.1.0 como "incremento 1 terminado", pero en main solo están T-01 a T-04 de 16 tareas (sección 14.8). | Consultar al profesor. Propuesta: publicar el plan ahora y crear v0.1.0 cuando se cierre T-16 (09/11/2026). |
| P-02 (nueva) | CA-001, CA-007, RF-10 | CA-001 y CA-007 piden que el balance del mes se actualice, pero el balance (RF-10) es del incremento 2. | En el incremento 1 se prueba guardado y lista; la parte del balance de CA-001 y CA-007 se prueba en el incremento 2. |
| P-03 (nueva; 14.3) | RF-09, CA-021, CA-023 | RF-09 borra el recibo asociado, pero los recibos se capturan en el incremento 3. | En el incremento 2 se borra también el registro de la tabla recibo (ya creada en la migración v1, 14.3). CA-023 (archivo de imagen) se prueba en el incremento 3 y queda en su regresión. |
| P-04 (nueva) | RF-53, CA-052 | RF-53 pide que persistan datos e imágenes, pero las imágenes llegan en el incremento 3. | En el incremento 1 se prueba la persistencia de datos (CA-147 a CA-149). CA-052 (imagen) se prueba en el incremento 3. |
| P-05 (nueva) | Restricciones | El documento no indica la fecha de entrega final. | Resuelta: el equipo confirmó la entrega el 23/11/2026, 18 días desde el 05/11/2026. |
| P-06 (nueva) | Alcance Must, 3.1 | Los RF Must suman 9.1 semanas-persona según 3.1, y del 05/11 al 23/11 hay unas 5.1 (2 personas, 18 días). | Se aplica la regla de recorte 3.3 (incrementos 6 y 7). Además se proponen los recortes R-A a R-D de la tabla de recortes, que requieren visto bueno del profesor porque cambian RF Must. |

## 5. Registro de cambios al plan

| Fecha | Cambio al plan | Motivo | Aprobado por |
|---|---|---|---|
| 05/11/2026 | Fechas de cierre: incremento 1 el 09/11, 2 el 11/11, 3 el 14/11, 4 el 18/11, 5 el 21/11 y cierre v1.0.0 el 23/11. | La entrega final es el 23/11/2026 (P-05). | Equipo |
| 05/11/2026 | Los incrementos 6 (búsqueda, filtros y sin conexión) y 7 (PIN) salen de la entrega: RF-32 a RF-35, RF-45 a RF-50 y RF-52. | Regla de recorte 3.3: son Should y no caben en 18 días (P-06). | Equipo; informar al profesor |
| 05/11/2026 | RNF-09 pasa al incremento 1 (solo la parte de la lista, CA-015) y RNF-43 pasa al cierre v1.0.0. | Antes estaban en el incremento 6, que se recortó. | Equipo |
| 05/11/2026 | Se crea el plan v1.0 con 7 incrementos y un cierre v1.0.0 (versión inicial, antes de conocer la fecha de entrega). | Práctica "plan de incrementos"; todo sale de las secciones 3 a 14 del documento. | Equipo (pendiente de confirmar) |
| 05/11/2026 | El incremento 1 se mantiene como "en curso": tiene T-01 a T-04 en main y faltan T-05 a T-16. | P-01: el incremento 1 aún no cumple su definición de terminado. | Profesor (pendiente) |
| 05/11/2026 | RF-51 (aviso de privacidad) pasa al incremento 5, junto con resumen y exportación. En el plan 3.2 estaba en la semana 7, con filtros y PIN. | Así los incrementos 1 a 5 tienen todos los RF Must, y la regla de recorte (3.3) solo afecta a los incrementos 6 y 7. | Equipo (pendiente de confirmar) |
