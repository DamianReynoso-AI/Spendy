import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/config/app_config.dart';
import 'package:spendy/config/categories.dart';

void main() {
  group('Categorías (RF-12, RF-13, RF-14)', () {
    test('CA-032 normal: egreso devuelve las 6 categorías en orden', () {
      expect(Categories.forType(MovementType.egreso), [
        'Alimentos',
        'Transporte',
        'Vivienda',
        'Servicios',
        'Entretenimiento',
        'Otros',
      ]);
    });

    test('CA-036 normal: ingreso devuelve solo sus 2 categorías', () {
      expect(Categories.forType(MovementType.ingreso),
          ['Sueldos y salarios', 'Otros ingresos']);
    });

    test('CA-038 error: ingreso no incluye categorías de egreso', () {
      expect(Categories.forType(MovementType.ingreso),
          isNot(contains('Alimentos')));
    });

    test('límite: las listas no se pueden modificar', () {
      expect(() => Categories.expenseCategories.add('Nueva'),
          throwsUnsupportedError);
    });

    test('el tipo se guarda como texto', () {
      expect(MovementType.egreso.value, 'egreso');
      expect(MovementType.ingreso.value, 'ingreso');
    });
  });

  group('Límites centrales (RNF-26)', () {
    test('valores definidos en RF-01 y RF-04', () {
      expect(AppConfig.maxAmountCents, (AppConfig.maxAmount * 100).round());
      expect(AppConfig.maxDescriptionLength, 60);
      expect(AppConfig.maxNoteLength, 200);
    });
  });
}
