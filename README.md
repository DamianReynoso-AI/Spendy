# SPENDY (Zenorbak 2)

App móvil en Flutter para registrar ingresos y egresos, tomar la foto de los
recibos, leerlos con OCR y exportar un resumen anual. Todo se guarda solo en
el teléfono (SQLite y carpeta privada de la app).

| Dato | Registro |
|---|---|
| Versión | 1.0.0 (cierre del 23/11/2026) |
| Equipo | Reynoso Nesme Hugo Damián (Operador de IA y Documentador) · Gutiérrez García Julio Augusto (Analista y Tester) |
| Curso | Desarrollo de Aplicaciones y Servicios Virtuales, UIA León |
| Plataforma del MVP | Android 10 (API 29) o superior (ALC-01, RNF-34) |
| Documentación | [Arquitectura](docs/arquitectura.md) · [Manual de usuario](docs/manual_usuario.md) · [Plan y reporte de pruebas](docs/plan_pruebas.md) · [Requerimientos](docs/requerimientos.pdf) · [Plan de incrementos](docs/plan_incrementos.md) |

Esta guía está pensada para que una persona ajena al equipo levante el
proyecto en 30 minutos o menos (RNF-46). Los tiempos de cada paso son
aproximados con una conexión doméstica.

## 1. Requisitos del entorno (≈ 10 min si falta algo)

| Herramienta | Versión probada | Para qué |
|---|---|---|
| Flutter SDK | 3.47.9 (canal stable) | Compilar y correr la app y las pruebas |
| Dart | 3.13.7 (viene con Flutter) | Lenguaje; el proyecto pide `sdk: ^3.5.0` |
| Android SDK | Plataforma 36 y build-tools (los instala Android Studio) | Compilar el APK |
| JDK | 17 | Gradle de Android |
| Teléfono o emulador | Android 10 (API 29) o superior, con cámara trasera | Correr la app |
| Git | Cualquier versión reciente | Clonar el repositorio |
| Python 3 | 3.8 o superior (opcional) | Script de revisión de calidad |

Comprueba todo con:

```bash
flutter --version     # debe decir Flutter 3.47.9 y Dart 3.13.7
flutter doctor        # Android toolchain y un dispositivo en verde
```

Las pruebas automáticas **no** necesitan Android SDK ni emulador: usan
SQLite del equipo (`sqflite_common_ffi`).

## 2. Clonar (≈ 1 min)

```bash
git clone https://github.com/DamianReynoso-AI/Spendy.git
cd Spendy
```

## 3. Configurar variables a partir de `.env.example` (≈ 2 min)

La lectura OCR usa un servicio externo. Su URL y su clave **nunca** van en
el código ni en el repositorio (RNF-18).

```bash
cp .env.example .env
# edita .env y llena SPENDY_OCR_ENDPOINT, SPENDY_OCR_API_KEY y SPENDY_OCR_PROVIDER_NAME
```

| Variable | Obligatoria | Descripción |
|---|---|---|
| `SPENDY_OCR_ENDPOINT` | No | URL `https://` del servicio de OCR. Una URL `http://` se rechaza (RNF-16). |
| `SPENDY_OCR_API_KEY` | No | Clave del servicio; se envía como `Authorization: Bearer <clave>`. |
| `SPENDY_OCR_PROVIDER_NAME` | No | Nombre del proveedor que se muestra en el aviso de privacidad. |

`.env` está en `.gitignore`. Si no configuras nada, la app funciona igual:
al escanear avisa que la lectura no está disponible y abre el registro
manual con la foto adjunta.

Contrato que debe cumplir el servicio de OCR (cualquier proveedor que lo
cumpla sirve; para otro contrato basta con otra implementación de
`OcrAdapter`, RNF-32):

```text
POST <SPENDY_OCR_ENDPOINT>
Authorization: Bearer <SPENDY_OCR_API_KEY>
Content-Type: image/jpeg
<bytes de la foto comprimida>

200 OK  {"text": "texto leído del recibo"}
```

## 4. Instalar dependencias (≈ 2 min)

```bash
flutter pub get
```

## 5. Ejecutar la app (≈ 5 a 10 min la primera compilación)

Conecta un teléfono Android con depuración USB o abre un emulador y corre:

```bash
flutter run --dart-define-from-file=.env
```

Sin `.env` también funciona (`flutter run`), pero sin lectura OCR.

Permisos ya declarados en `android/app/src/main/AndroidManifest.xml`:
`CAMERA` (foto del recibo) e `INTERNET` (solo para el OCR, siempre por
HTTPS). Las fotos se guardan en la carpeta privada de la app (`recibos/`,
con `.nomedia`), nunca en la galería (RNF-14).

Para generar un APK de prueba: `flutter build apk --dart-define-from-file=.env`.

## 6. Pruebas con un solo comando (≈ 1 min)

```bash
flutter test
```

Corre las pruebas unitarias (`test/unit`), de pantallas (`test/widget`) y de
integración (`test/integration`). Con cobertura:

```bash
flutter test --coverage      # reporte en coverage/lcov.info
```

Otras revisiones de la definición de terminado:

```bash
flutter analyze              # RNF-24: debe decir "No issues found!"
python3 tool/check_quality.py   # RNF-29 (≤ 50 líneas, complejidad ≤ 10) y RNF-30 (lib/ui no importa lib/data)
flutter pub outdated         # RNF-23: auditoría de dependencias
```

`tool/check_quality.py` es una revisión aproximada hecha con un script; no
sustituye a un analizador de métricas.

En GitHub Actions (`.github/workflows/pruebas.yml`) corren solos `flutter
analyze`, `tool/check_quality.py` y `flutter test --coverage` en cada push
y en cada pull request a `main` (RNF-41).

### Prueba de OCR con 30 recibos reales (RNF-42, RNF-13)

`test/integration/receipts_accuracy_test.dart` se omite mientras no estén las
fotos y la configuración. Para correrla, sigue
[`test/fixtures/receipts/README.md`](test/fixtures/receipts/README.md) y:

```bash
set -a; source .env; set +a
flutter test test/integration/receipts_accuracy_test.dart
```

## 7. Estructura del proyecto

```text
lib/
  main.dart            arma los servicios (único lugar fuera de M-11 que conoce lib/data/)
  app.dart             raíz de la interfaz, idioma fijo es-MX, aviso de primer inicio
  config/              M-12: límites, categorías y textos del aviso (RNF-26)
  core/                M-12 y M-13: formatos, validadores, Result y errores.log
  data/                M-11: SQLite, migraciones, repositorios e imágenes privadas
  modules/             lógica de negocio: movements, categories, receipts, ocr,
                       search, summary, export, privacy (M-02 a M-10)
  ui/                  M-01: pantallas y widgets
test/                  unit/, widget/, integration/ y fixtures/
docs/                  arquitectura, manual, plan de pruebas, requerimientos
android/               proyecto Android (plataforma del MVP)
tool/check_quality.py  revisión de RNF-29 y RNF-30
```

La descripción completa de capas, módulos y modelo de datos está en
[docs/arquitectura.md](docs/arquitectura.md).

## 8. Módulos y versiones

| Versión | Contenido |
|---|---|
| v0.1.0 | Registrar y consultar movimientos (M-02, M-03, M-11, M-12, M-13, M-01) |
| v0.2.0 | Editar, eliminar y balance del mes |
| v0.3.0 | Recibos con cámara (M-04) |
| v0.4.0 | Lectura OCR con confirmación (M-05) |
| v0.5.0 | Resumen anual, exportación CSV/PDF y aviso de privacidad (M-07, M-08, M-10) |
| v0.6.0 | Búsqueda, filtros y uso sin conexión (M-06) |
| v1.0.0 | Cierre: verificación de RNF, saneamiento de defectos y documentación |
| v0.7.0 | Protección con PIN (M-09), posterior al 23/11/2026; ver la sección PIN de la arquitectura y del manual |

## 9. Problemas comunes

| Síntoma | Solución |
|---|---|
| `flutter run` dice que no hay dispositivos | Activa la depuración USB del teléfono o abre un emulador desde Android Studio (Device Manager). |
| Al escanear dice que la lectura no está disponible | Falta `.env` o no se pasó `--dart-define-from-file=.env`; o la URL no es `https://`. |
| Gradle pide otra versión de Java | Usa JDK 17 (`flutter config --jdk-dir <ruta>`). |
| `flutter analyze` marca archivos de `build/` | Ya están excluidos en `analysis_options.yaml`; corre `flutter clean` y vuelve a intentar. |
