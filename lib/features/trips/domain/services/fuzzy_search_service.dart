import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fuzzySearchProvider = Provider<FuzzySearchService>((ref) {
  return FuzzySearchService();
});

class FuzzySearchService {
  List<String> _clients = [];
  bool _isLoaded = false;

  // Llama a esto al iniciar la app para cargar los clientes a la memoria RAM
  Future<void> loadClientsFromAsset(String assetPath) async {
    if (_isLoaded) return;
    try {
      final data = await rootBundle.loadString(assetPath);
      _clients = data.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      _isLoaded = true;
    } catch (e) {
      // Manejar error en caso de que el archivo no exista
      _clients = [];
    }
  }

  // Motor de Búsqueda Difusa (Fuzzy Search)
  List<String> search(String query) {
    if (query.isEmpty) return [];

    final normalizedQuery = _normalize(query);
    final queryTokens = normalizedQuery.split(' ');

    List<Map<String, dynamic>> results = [];

    for (String client in _clients) {
      final normalizedClient = _normalize(client);
      
      int score = 0;
      bool matchesAllTokens = true;

      // El cliente debe contener TODAS las palabras clave buscadas (en cualquier orden)
      for (String token in queryTokens) {
        if (token.isEmpty) continue;
        
        if (!normalizedClient.contains(token)) {
          matchesAllTokens = false;
          break;
        } else {
          // Puntuación: Si la palabra empieza exactamente igual, suma más puntos
          if (normalizedClient.startsWith(token) || normalizedClient.contains(' $token')) {
            score += 10;
          }
          score += token.length;
        }
      }

      if (matchesAllTokens) {
        results.add({'client': client, 'score': score});
      }
    }

    // Ordenar de mayor a menor puntuación
    results.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    
    // Devolver solo los 10 mejores resultados para no saturar la pantalla
    return results.take(10).map((e) => e['client'] as String).toList();
  }

  // Limpia el texto: Quita tildes, puntos, comas y lo pasa a minúscula
  String _normalize(String input) {
    var normalized = input.toLowerCase();
    const withDia = 'áéíóúüñ';
    const withoutDia = 'aeiouun';
    
    for (int i = 0; i < withDia.length; i++) {
      normalized = normalized.replaceAll(withDia[i], withoutDia[i]);
    }
    
    return normalized
        .replaceAll(RegExp(r'[^\w\s]'), ' ') // Reemplaza puntuación por espacios
        .replaceAll(RegExp(r'\s+'), ' ') // Colapsa múltiples espacios
        .trim();
  }
}
