/// M-11 · Apertura de la base SQLite (RF-53; RNF-14, RNF-27).
///
/// La base vive en la carpeta privada de bases de datos de la app, con
/// llaves foráneas activas. El esquema se crea y se actualiza con
/// migraciones numeradas (RNF-27): una base nueva corre todas; una que ya
/// existe solo corre las que le faltan, sin perder datos.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations/v1_initial.dart';
import 'migrations/v2_budgets.dart';
import 'migrations/v3_integrity.dart';

/// Nombre del archivo de la base dentro del almacenamiento privado.
const String databaseFileName = 'spendy.db';

/// Versión actual del esquema (RNF-27).
const int schemaVersion = V3Integrity.version;

/// Pasos de actualización: la llave es la versión a la que lleva cada uno.
/// La v1 es la creación inicial y la corre [_onCreate].
final Map<int, Future<void> Function(Transaction)> _upgrades = {
  V2Budgets.version: V2Budgets.apply,
  V3Integrity.version: V3Integrity.apply,
};

/// Base nueva: esquema inicial más todas las migraciones, en una sola
/// transacción (si algo falla no queda a medias).
Future<void> _onCreate(Database db, int version) => db.transaction((txn) async {
      await V1Initial.applyIn(txn);
      await _migrate(txn, V1Initial.version, version);
    });

/// Base existente con una versión anterior: corre solo lo que falta.
Future<void> _onUpgrade(Database db, int from, int to) =>
    db.transaction((txn) => _migrate(txn, from, to));

Future<void> _migrate(Transaction txn, int from, int to) async {
  for (var v = from + 1; v <= to; v++) {
    final step = _upgrades[v];
    if (step == null) throw StateError('Falta la migración a la versión $v');
    await step(txn);
  }
}

/// Opciones de apertura comunes a la app y a las pruebas.
OpenDatabaseOptions spendyDatabaseOptions() => OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

/// Abre (o crea) la base de SPENDY.
///
/// [factory] y [path] permiten usar SQLite en memoria en las pruebas; en la
/// app se usa la fábrica de sqflite y la carpeta privada de la app.
Future<Database> openSpendyDatabase({
  DatabaseFactory? factory,
  String? path,
}) async {
  final dbFactory = factory ?? databaseFactory;
  final dbPath =
      path ?? p.join(await dbFactory.getDatabasesPath(), databaseFileName);
  return dbFactory.openDatabase(dbPath, options: spendyDatabaseOptions());
}

/// Tablas con datos de la persona usuaria, en orden de borrado (primero
/// las que apuntan a otras). `categoria` es catálogo fijo y se conserva.
const List<String> userDataTables = [
  'recibo',
  'presupuesto',
  'movimiento',
  'ajuste',
];

/// Borrado total de los datos de la base para el restablecimiento de la
/// app (RF-50; CA-137, CA-139).
///
/// Todo ocurre en una sola transacción: si la app se cierra a mitad, la
/// base conserva todos sus datos; si termina, queda como recién creada
/// (sin movimientos, recibos ni ajustes, con el catálogo de categorías).
/// También reinicia los contadores de AUTOINCREMENT.
Future<void> wipeUserData(Database db) => db.transaction((txn) async {
      for (final table in userDataTables) {
        await txn.delete(table);
      }
      await txn.delete('sqlite_sequence');
    });
