/// M-01 · Campo de monto (RF-04, D-03).
///
/// Acepta dígitos, punto y coma. La coma se deja escribir a propósito: si se
/// filtrara, "12,5" se volvería "125" y se guardaría un valor equivocado
/// (CA-151). El servicio la rechaza con un mensaje claro.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Campo de texto para el monto en pesos.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.errorText,
    this.onChanged,
  });

  /// Monto máximo "9999999.99" más un margen para que el validador muestre
  /// su mensaje en lugar de cortar el texto en silencio.
  static const int maxInputLength = 16;

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        LengthLimitingTextInputFormatter(maxInputLength),
      ],
      decoration: InputDecoration(
        labelText: 'Monto *',
        hintText: 'Por ejemplo, 350.00',
        prefixText: r'$ ',
        helperText: 'Usa punto para los decimales.',
        errorText: errorText,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
