/// M-03 · Catálogo de categorías por tipo de movimiento (RF-12 a RF-14).
///
/// La interfaz pide aquí las categorías; nunca lee la base (RNF-30).
library;

import '../../config/categories.dart';
import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/repositories/category_repository.dart';

export '../../config/categories.dart' show MovementType;

/// Categoría lista para mostrarse en el selector.
class CategoryOption {
  const CategoryOption({
    required this.id,
    required this.name,
    required this.type,
  });

  final int id;
  final String name;
  final MovementType type;
}

/// Catálogo de solo lectura. Lee la base una vez y guarda el resultado,
/// porque las categorías son fijas.
class CategoryCatalog {
  CategoryCatalog(this._repository, this._logger);

  static const String module = 'M-03';

  final CategoryRepository _repository;
  final ErrorLogger _logger;
  List<CategoryOption>? _cache;

  /// Categorías del tipo pedido, en su orden fijo (RF-14).
  Future<Result<List<CategoryOption>>> forType(MovementType type) async {
    final all = await _loadAll();
    return switch (all) {
      Success(:final value) => Success(
          value.where((c) => c.type == type).toList(growable: false),
        ),
      Failure(:final error) => Failure(error),
    };
  }

  /// `true` si la categoría existe y es del mismo tipo que el
  /// movimiento (RF-14, CA-010, CA-038).
  Future<Result<bool>> belongsToType(int categoryId, MovementType type) async {
    final all = await _loadAll();
    return switch (all) {
      Success(:final value) => Success(
          value.any((c) => c.id == categoryId && c.type == type),
        ),
      Failure(:final error) => Failure(error),
    };
  }

  Future<Result<List<CategoryOption>>> _loadAll() async {
    final cached = _cache;
    if (cached != null) return Success(cached);
    try {
      final records = await _repository.fetchAll();
      final options = records
          .map((r) => CategoryOption(id: r.id, name: r.name, type: r.type))
          .toList(growable: false);
      _cache = options;
      return Success(options);
    } on Object catch (e) {
      final error = translateStorageError(e, writing: false);
      await _logger.log(type: error.type, module: module, cause: e);
      return Failure(error);
    }
  }
}
