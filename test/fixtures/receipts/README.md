# Recibos reales para RNF-42 y RNF-13

Aquí van las 30 fotos de recibos reales y sus totales correctos. La prueba
`test/integration/receipts_accuracy_test.dart` las envía al proveedor de OCR
real y mide:

- RNF-42: al menos 80 % de los totales leídos coinciden con el real.
- RNF-13: al menos 90 % de las lecturas tardan 8 s o menos.

## Formato

1. Copia las fotos (`.jpg`) a esta carpeta.
2. Crea `expected.json` con el total correcto de cada foto:

```json
[
  {"file": "recibo_01.jpg", "total": "39.50"},
  {"file": "recibo_02.jpg", "total": "1250.00"}
]
```

3. Corre la prueba con el proveedor configurado (nunca subas la clave):

```bash
SPENDY_OCR_ENDPOINT=https://... SPENDY_OCR_API_KEY=... \
  flutter test test/integration/receipts_accuracy_test.dart
```

Si faltan las fotos, `expected.json` o la configuración, la prueba se
marca como omitida y no inventa resultados.
