import 'dart:convert';
import 'package:http/http.dart' as http;

class TaxIndicatorService {
  /// Obtiene el historial de UTM para un año específico desde mindicador.cl
  /// Retorna un mapa con formato {"YYYY-MM": valor}
  Future<Map<String, double>> fetchUtmYearlyHistory(int year) async {
    try {
      final response = await http.get(Uri.parse('https://mindicador.cl/api/utm/$year'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List serie = data['serie'] ?? [];
        final Map<String, double> history = {};
        
        // La API entrega los datos de más reciente a más antiguo
        for (var item in serie) {
          final DateTime date = DateTime.parse(item['fecha']);
          final String key = "${date.year}-${date.month.toString().padLeft(2, '0')}";
          
          // Guardamos el valor (usualmente solo hay uno por mes)
          history[key] = (item['valor'] as num).toDouble();
        }
        
        return history;
      } else {
        return {};
      }
    } catch (e) {
      // En caso de error de red o de la API, retornamos mapa vacío
      return {};
    }
  }
}
