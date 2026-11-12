/// M-11 · Lectura y escritura de ajustes en la tabla `ajuste` (sección
/// 13.4; RF-51).
library;

import 'package:sqflite/sqflite.dart';

/// Acceso a la tabla `ajuste (clave, valor, actualizado_en)`.
class SettingsRepository {
  SettingsRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DatabaseExecutor _db;
  final DateTime Function() _clock;

  /// Valor guardado para [clave], o `null` si no existe.
  Future<String?> getSetting(String clave) async {
    final rows = await _db.query(
      'ajuste',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [clave],
    );
    return rows.isEmpty ? null : rows.first['valor'] as String;
  }

  /// Guarda [valor] para [clave] (lo crea o lo reemplaza) con la fecha y
  /// hora actual en ISO 8601 en `actualizado_en`.
  Future<void> setSetting(String clave, String valor) => _db.insert(
        'ajuste',
        {
          'clave': clave,
          'valor': valor,
          'actualizado_en': _clock().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
