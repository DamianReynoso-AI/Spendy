/// M-11 · Apertura de la base SQLite (RF-53; RNF-14, RNF-27).
///
/// La base vive en la carpeta privada de bases de datos de la app, con
/// llaves foráneas activas y versión de esquema 1 (migración v1_initial).
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations/v1_initial.dart';

/// Nombre del archivo de la base dentro del almacenamiento privado.
const String databaseFileName = 'spendy.db';

/// Versión actual del esquema (RNF-27).
const int schemaVersion = V1Initial.version;

/// Opciones de apertura comunes a la app y a las pruebas.
OpenDatabaseOptions spendyDatabaseOptions() => OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: V1Initial.apply,
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
