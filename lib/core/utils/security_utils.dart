class SecurityUtils {
  /// Elimina etiquetas HTML y scripts básicos para prevenir XSS simple
  /// en el panel de administración web.
  static String sanitizeText(String text) {
    if (text.isEmpty) return text;
    
    // Eliminar etiquetas HTML usando Regex simple
    // <[^>]*> coincide con cualquier cosa que parezca una etiqueta HTML
    final sanitized = text.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '');
    
    // Podríamos añadir más filtros aquí si es necesario
    return sanitized.trim();
  }
}
