# Firma del APK de lanzamiento (AUD-02)

El APK de lanzamiento de SPENDY se firma siempre con la misma llave. Si cambia
la llave, Android no deja instalar la versión nueva encima de la anterior: hay
que desinstalar y se pierden los datos. Por eso la compilación `release` falla
si no encuentra la llave.

## Dónde vive la llave

- `spendy-release.jks`: almacén de llaves (alias `spendy`, RSA 4096, 30 años).
- `android/key.properties`: rutas y contraseñas. **No se sube a Git**
  (`android/.gitignore` ignora `key.properties` y `*.jks`).

Formato de `android/key.properties`:

```properties
storeFile=/ruta/completa/a/spendy-release.jks
storePassword=...
keyAlias=spendy
keyPassword=...
```

## Respaldo (obligatorio)

Guarda `spendy-release.jks` y sus contraseñas en **dos** lugares seguros (por
ejemplo, un gestor de contraseñas y una memoria USB guardada). Si se pierde, no
habrá forma de publicar actualizaciones que se instalen encima.

## Crear una llave nueva (solo si no existe)

```bash
keytool -genkeypair -v -keystore spendy-release.jks -alias spendy \
  -keyalg RSA -keysize 4096 -validity 10950 \
  -dname "CN=Zenorbak 2, O=Zenorbak 2, L=Leon, ST=Guanajuato, C=MX"
```

## Compilar

```bash
flutter build apk --release --dart-define=SPENDY_GEMINI_API_KEY=<clave>
```

Sin `--target-platform`: así el APK trae arm64, armeabi-v7a y x86_64 y abre
en cualquier teléfono y en emuladores como appetize.io.

La clave de Gemini es la del equipo (Google AI Studio) y nunca se sube al
repositorio. Va dentro del APK, así que quien lo tenga puede extraerla: en
AI Studio ponle restricción de app Android (`mx.zenorbak.spendy` + huella
SHA-1 de la llave de firma) o un límite de cuota. Si la rotas, recompila.

Para una prueba interna sin la llave (no se puede instalar encima de una
versión firmada):

```bash
SPENDY_ALLOW_DEBUG_SIGNING=1 flutter build apk --release
```

## Google Play

Al publicar, activa *Play App Signing*: Google guarda la llave de firma de la
app y esta llave queda como llave de subida.
