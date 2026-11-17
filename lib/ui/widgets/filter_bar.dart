/// M-01 · Barra de búsqueda y filtros de la lista (RF-32, RF-33, RF-35;
/// CA-083, CA-089, CA-091).
///
/// Solo arma los criterios; quien la usa los aplica con M-06. No importa
/// `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../modules/categories/category_catalog.dart';
import '../../modules/search/movement_filter.dart';

/// Texto, rango de fechas, tipo, categoría y "Limpiar filtros".
class FilterBar extends StatefulWidget {
  const FilterBar({
    super.key,
    required this.criteria,
    required this.categories,
    required this.onChanged,
  });

  final MovementCriteria criteria;

  /// Categorías de ingreso y de egreso para el selector.
  final List<CategoryOption> categories;
  final ValueChanged<MovementCriteria> onChanged;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final TextEditingController _text =
      TextEditingController(text: widget.criteria.text);

  MovementCriteria get _criteria => widget.criteria;

  @override
  void didUpdateWidget(FilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_criteria.text != _text.text) _text.text = _criteria.text;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _criteria.startDate : _criteria.endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: start ? 'Fecha inicial' : 'Fecha final',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked == null) return;
    widget.onChanged(
      start
          ? _criteria.copyWith(startDate: () => picked)
          : _criteria.copyWith(endDate: () => picked),
    );
  }

  /// Al cambiar el tipo, la categoría elegida se borra si ya no es de ese
  /// tipo.
  void _changeType(MovementType? type) {
    final category = _criteria.categoryId;
    final keep = type == null ||
        widget.categories.any((c) => c.id == category && c.type == type);
    widget.onChanged(
      _criteria.copyWith(
        type: () => type,
        categoryId: () => keep ? category : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            onChanged: (text) =>
                widget.onChanged(_criteria.copyWith(text: text)),
            decoration: const InputDecoration(
              labelText: 'Buscar en descripción o nota',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          _dateRow(),
          const SizedBox(height: 8),
          _typeSelector(),
          const SizedBox(height: 8),
          _categorySelector(),
          if (!_criteria.isEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => widget.onChanged(const MovementCriteria()),
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Limpiar filtros'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateRow() {
    String label(String name, DateTime? date) =>
        date == null ? name : '$name: ${formatDate(date)}';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _pickDate(start: true),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(label('Desde', _criteria.startDate)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => _pickDate(start: false),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(label('Hasta', _criteria.endDate)),
          ),
        ),
      ],
    );
  }

  Widget _typeSelector() {
    return SegmentedButton<MovementType?>(
      segments: const [
        ButtonSegment(value: null, label: Text('Todos')),
        ButtonSegment(value: MovementType.ingreso, label: Text('Ingreso')),
        ButtonSegment(value: MovementType.egreso, label: Text('Egreso')),
      ],
      selected: {_criteria.type},
      onSelectionChanged: (s) => _changeType(s.first),
    );
  }

  Widget _categorySelector() {
    final type = _criteria.type;
    final options =
        widget.categories.where((c) => type == null || c.type == type);
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Categoría',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _criteria.categoryId,
          isExpanded: true,
          isDense: true,
          items: [
            const DropdownMenuItem<int?>(child: Text('Todas')),
            for (final c in options)
              DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
          ],
          onChanged: (id) => widget.onChanged(
            _criteria.copyWith(categoryId: () => id),
          ),
        ),
      ),
    );
  }
}
