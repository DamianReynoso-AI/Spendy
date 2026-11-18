/// M-09 · Reloj monótono del teléfono (AUD-04).
///
/// `SystemClock.elapsedRealtime()` de Android: milisegundos desde que se
/// encendió el teléfono. No cambia si la persona ajusta la hora, así que
/// sirve para que el bloqueo del PIN no se quite adelantando el reloj. Se
/// reinicia al apagar el teléfono; por eso se usa junto con la hora normal.
library;

import 'package:flutter/services.dart';

/// Devuelve los milisegundos del reloj monótono, o `null` si la plataforma
/// no lo ofrece (pruebas, escritorio).
typedef UptimeClock = Future<int?> Function();

const MethodChannel _channel = MethodChannel('mx.zenorbak.spendy/clock');

/// Lee `elapsedRealtime` por el canal de [MainActivity]. Cualquier error
/// (sin canal, sin binding) se trata como "no disponible".
Future<int?> platformUptime() async {
  try {
    return await _channel.invokeMethod<int>('elapsedRealtime');
  } on Object {
    return null;
  }
}

/// Sin reloj monótono: el bloqueo depende solo de la hora del teléfono.
Future<int?> noUptime() async => null;
