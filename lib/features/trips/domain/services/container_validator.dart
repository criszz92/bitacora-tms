/// Validador de Números de Contenedor según la norma ISO 6346.
///
/// Formato esperado (sin guión, 11 caracteres):
///   [3 letras propietario][U][6 dígitos serie][1 dígito verificador]
///   Ejemplo: MSMU3836691  →  almacenado como MSMU383669-1
class ContainerValidator {
  /// Valores numéricos de cada letra según tabla ISO 6346.
  /// Nótese que I, O, T no existen para evitar confusión con 1, 0, T.
  static const Map<String, int> _letterValues = {
    'A': 10, 'B': 12, 'C': 13, 'D': 14, 'E': 15, 'F': 16, 'G': 17,
    'H': 18, 'I': 19, 'J': 20, 'K': 21, 'L': 23, 'M': 24, 'N': 25,
    'O': 26, 'P': 27, 'Q': 28, 'R': 29, 'S': 30, 'T': 31, 'U': 32,
    'V': 34, 'W': 35, 'X': 36, 'Y': 37, 'Z': 38,
  };

  /// Limpia el input: elimina guiones, espacios y convierte a mayúsculas.
  static String clean(String input) =>
      input.trim().toUpperCase().replaceAll(RegExp(r'[-\s]'), '');

  /// Devuelve `null` si el número es válido según ISO 6346.
  /// Devuelve un mensaje de error descriptivo si no lo es.
  static String? validate(String? input) {
    if (input == null || input.trim().isEmpty) return null; // Puede ser opcional según contexto

    final raw = clean(input);

    if (raw.length != 11) {
      return 'Debe tener 11 caracteres sin guión · Ej: MSMU3836691';
    }

    // Las primeras 4 posiciones deben ser letras
    final prefix = raw.substring(0, 4);
    if (!RegExp(r'^[A-Z]{4}$').hasMatch(prefix)) {
      return 'Los primeros 4 caracteres deben ser letras · Ej: MSMU…';
    }

    // La 4ª letra SIEMPRE debe ser U (freight container)
    if (prefix[3] != 'U') {
      return 'El 4° carácter debe ser "U" · Ej: MSMU… / MSCU…';
    }

    // Posiciones 5–10 deben ser dígitos (número de serie)
    final serial = raw.substring(4, 10);
    if (!RegExp(r'^\d{6}$').hasMatch(serial)) {
      return 'Los caracteres 5-10 deben ser números (serie)';
    }

    // La posición 11 es el dígito verificador
    final checkChar = raw[10];
    if (!RegExp(r'^\d$').hasMatch(checkChar)) {
      return 'El último carácter debe ser un dígito verificador (0-9)';
    }

    // Verificación matemática ISO 6346
    final expectedCheck = _calculateCheckDigit(raw.substring(0, 10));
    final actualCheck = int.parse(checkChar);

    if (actualCheck != expectedCheck) {
      return 'Dígito verificador incorrecto · Correcto: $expectedCheck';
    }

    return null; // ✓ Válido
  }

  /// Calcula el dígito verificador de los primeros 10 caracteres.
  static int _calculateCheckDigit(String first10) {
    int sum = 0;
    for (int i = 0; i < 10; i++) {
      final char = first10[i];
      final int value;
      if (RegExp(r'[A-Z]').hasMatch(char)) {
        value = _letterValues[char] ?? 0;
      } else {
        value = int.parse(char);
      }
      sum += value * (1 << i); // value × 2^i
    }
    final remainder = sum % 11;
    return remainder == 10 ? 0 : remainder; // Si 10, el verificador es 0
  }

  /// Formatea para mostrar: MSMU3836691 → MSMU383669-1
  static String format(String input) {
    final raw = clean(input);
    if (raw.length == 11) {
      return '${raw.substring(0, 10)}-${raw[10]}';
    }
    return raw;
  }

  /// Valida solo si es obligatorio (cuando el campo no puede estar vacío).
  static String? validateRequired(String? input) {
    if (input == null || clean(input).isEmpty) return 'El número de contenedor es obligatorio';
    return validate(input);
  }
}
