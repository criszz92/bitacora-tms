import 'package:flutter/services.dart';

class NumberUtils {
  static double? tryParseDouble(String? input) {
    if (input == null || input.isEmpty) return null;
    
    // 1. Convertimos comas a puntos
    // 2. Eliminamos cualquier cosa que no sea número o punto ($, espacios, etc)
    final String cleaned = input
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^0-9.]'), '');
    
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static TextInputFormatter get commaToPointFormatter =>
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

  /// Formatea un número como moneda chilena con puntos de miles (ej: 1.500.000)
  static String formatCurrency(num? value) {
    if (value == null) return '0';
    final intValue = value.round();
    final str = intValue.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(str[i]);
    }
    return (intValue < 0 ? '-' : '') + buffer.toString();
  }
}

class DecimalTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String t = newValue.text.replaceAll(',', '.');
    if ('.'.allMatches(t).length > 1) return oldValue;
    return TextEditingValue(
      text: t,
      selection: newValue.selection,
    );
  }
}
