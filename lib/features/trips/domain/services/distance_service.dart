import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Servicio de sugerencia de kilómetros basado en la tabla de distancias
/// cliente-puerto generada desde distancias_clientes_puertos.xlsx.
///
/// Carga el JSON en RAM al iniciar la app (similar a FuzzySearchService)
/// y expone [lookupKm] para sugerir KM al finalizar un viaje.
class DistanceService {
  Map<String, dynamic> _data = {};
  bool _loaded = false;

  /// Mapa de alias para normalizar nombres de puertos en el destino del viaje
  static const _portAliases = <String, String>{
    'SAN ANTONIO': 'Pto San Antonio',
    'PTO SAN ANTONIO': 'Pto San Antonio',
    'PUERTO SAN ANTONIO': 'Pto San Antonio',
    'VALPARAISO': 'Pto Valparaiso',
    'VALPARAÍSO': 'Pto Valparaiso',
    'PTO VALPARAISO': 'Pto Valparaiso',
    'PUERTO VALPARAISO': 'Pto Valparaiso',
    'SAN VICENTE': 'Pto San Vicente',
    'PTO SAN VICENTE': 'Pto San Vicente',
    'CORONEL': 'Pto Coronel',
    'PTO CORONEL': 'Pto Coronel',
    'LIRQUEN': 'Pto Lirquen',
    'LIRQUÉN': 'Pto Lirquen',
    'PTO LIRQUEN': 'Pto Lirquen',
    'ANTOFAGASTA': 'Pto Antofagasta',
    'PTO ANTOFAGASTA': 'Pto Antofagasta',
  };

  /// Carga el JSON de distancias desde los assets. Llamar una sola vez al inicio.
  Future<void> loadFromAsset(String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      _data = jsonDecode(raw) as Map<String, dynamic>;
      _loaded = true;
    } catch (_) {
      // Fallo silencioso — la función de sugerencia simplemente devuelve null
    }
  }

  /// Permite inyectar datos para testing unitario sin requerir rootBundle.
  void loadDataForTesting(Map<String, dynamic> data) {
    _data = data;
    _loaded = true;
  }

  /// Busca la distancia entre [cliente] y [destino] (puerto).
  /// Devuelve los KM sugeridos o null si no hay datos suficientes.
  ///
  /// [cliente] — Nombre del cliente (fuzzy-tolerante, en mayúsculas o no).
  /// [destino] — Nombre del destino/puerto del viaje.
  double? lookupKm(String cliente, String destino) {
    if (!_loaded || _data.isEmpty) return null;

    final clienteKey = cliente.trim().toUpperCase();
    final entry = _data[clienteKey] as Map<String, dynamic>?;
    if (entry == null) return null;

    // Intentar con el puerto específico del destino
    final destinoKey = destino.trim().toUpperCase();
    final portKey = _portAliases[destinoKey];

    if (portKey != null) {
      final distancias = entry['distancias'] as Map<String, dynamic>?;
      final km = distancias?[portKey];
      if (km != null && km is num && km > 0) return km.toDouble();
    }

    // Fallback: devolver el KM mínimo (puerto más cercano al cliente)
    final kmMin = entry['kmMinimo'];
    if (kmMin != null && kmMin is num && kmMin > 0) return kmMin.toDouble();

    return null;
  }

  /// Devuelve el nombre del puerto más cercano al cliente, si se conoce.
  String? nearestPort(String cliente) {
    if (!_loaded || _data.isEmpty) return null;
    final entry = _data[cliente.trim().toUpperCase()] as Map<String, dynamic>?;
    return entry?['puertoMasCercano'] as String?;
  }

  bool get isLoaded => _loaded;
  int get clientCount => _data.length;
}

/// Provider global — se inicializa con override en main.dart igual que fuzzySearchProvider
final distanceServiceProvider = Provider<DistanceService>((ref) => DistanceService());
