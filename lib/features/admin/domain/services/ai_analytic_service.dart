import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/analytics_models.dart';

class AIAnalyticService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> _getAiApiKey() async {
    try {
      final doc = await _firestore.collection('secrets').doc('ai_config').get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['apiKey'] as String;
      }
      throw Exception("No se encontró la API Key en el cofre seguro.");
    } catch (e) {
      throw Exception("Error accediendo al cofre de seguridad: $e");
    }
  }

  Future<String> analyzeRouteProfitability(List<RouteProfitability> data) async {
    try {
      // 1. Obtener la llave del cofre de Firestore (Solo ADMIN puede)
      final apiKey = await _getAiApiKey();
      const baseUrl = 'https://api.groq.com/openai/v1';

      // 2. Preparar los datos
      final summary = data.map((r) => {
        'ruta': r.route,
        'viajes': r.tripCount,
        'ingresos': r.totalIncome,
        'margen': r.netMargin,
        'porcentaje': r.marginPercentage,
        'cpk': r.totalKm > 0 ? (r.totalFuelCost + r.totalTolls + r.totalPersonal + r.totalMaintenance) / r.totalKm : 0,
      }).toList();

      final prompt = """
      Eres un experto en logística y finanzas de transporte (TMS).
      Analiza los siguientes datos de rentabilidad de rutas del mes actual:
      $summary

      Por favor, proporciona:
      1. Un resumen ejecutivo de la salud financiera de la flota.
      2. Identifica la ruta más rentable y por qué.
      3. Identifica la ruta con problemas y sugiere una acción correctiva.
      4. Una recomendación estratégica para el próximo mes.

      Responde en español, de forma profesional y concisa. Usa bullet points.
      """;

      final response = await http.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {'role': 'system', 'content': 'Eres un asistente experto en analítica de transporte.'},
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        return jsonResponse['choices'][0]['message']['content'];
      } else {
        return "Error en la IA (${response.statusCode}): ${response.body}";
      }
    } catch (e) {
      return "Error en el asistente: $e";
    }
  }

  Future<String> askOperationalAssistant({
    required String question,
    required List<RouteProfitability> data,
    List<Map<String, String>> history = const [],
  }) async {
    try {
      final apiKey = await _getAiApiKey();
      const baseUrl = 'https://api.groq.com/openai/v1';

      final summary = data.map((r) => {
        'ruta': r.route,
        'viajes': r.tripCount,
        'ingresos': r.totalIncome,
        'margen': r.netMargin,
        'cpk': r.totalKm > 0 ? (r.totalFuelCost + r.totalTolls + r.totalPersonal + r.totalMaintenance) / r.totalKm : 0,
      }).toList();

      final systemPrompt = """
      Eres "Bitácora AI", el Asistente Experto en Operaciones Logísticas de la empresa.
      
      TU MISIÓN: Ayudar al administrador a entender la rentabilidad, costos y eficiencia de su flota.
      
      DATOS ACTUALES DE LA OPERACIÓN:
      $summary

      REGLAS CRÍTICAS DE COMPORTAMIENTO:
      1. SOLO respondes preguntas sobre logística, transporte, camiones, gastos de viaje, rentabilidad y datos presentes en Bitácora.
      2. Si el usuario pregunta algo fuera de este contexto (ej: medicina, mascotas, chistes, temas generales, etc), debes responder exactamente: "Lo siento, como tu Asistente de Operaciones Bitácora, solo puedo ayudarte con temas relacionados a la logística y rentabilidad de tu flota."
      3. Sé conciso, profesional y directo.
      4. Si te piden cálculos, usa los datos proporcionados arriba.
      """;

      final messages = [
        {'role': 'system', 'content': systemPrompt},
        ...history,
        {'role': 'user', 'content': question},
      ];

      final response = await http.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': messages,
          'temperature': 0.3, // Menos creativo, más preciso
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        return jsonResponse['choices'][0]['message']['content'];
      } else {
        return "Error en la consulta: ${response.statusCode}";
      }
    } catch (e) {
      return "Error de conexión: $e";
    }
  }
}
