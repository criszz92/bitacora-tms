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
