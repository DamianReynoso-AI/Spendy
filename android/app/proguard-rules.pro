# SPENDY · Reglas de R8 para la compilación release.
# google_mlkit_text_recognition hace referencia a los modelos de chino,
# devanagari, japonés y coreano, que no se incluyen (solo se usa el latino).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
