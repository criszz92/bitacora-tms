import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/analytics_models.dart';
import 'gps_harvest_service.dart';

class _AiConfig {
  final String apiKey;
  final String? model;

  _AiConfig({required this.apiKey, this.model});
}

class AIAnalyticService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<_AiConfig> _getAiConfig() async {
    try {
      final doc = await _firestore.collection('secrets').doc('ai_config').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final apiKey = data['apiKey'] as String?;
        if (apiKey != null && apiKey.isNotEmpty) {
          final model = data['model'] as String?;
          return _AiConfig(apiKey: apiKey, model: model);
        }
      }
      throw Exception("No se encontró la API Key en el cofre seguro.");
    } catch (e) {
      throw Exception("Error accediendo al cofre de seguridad: $e");
    }
  }

  Future<String> _callGroqChat({
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    String? preferredModel,
  }) async {
    const baseUrl = 'https://api.groq.com/openai/v1';

    // Modelos candidatos en orden de prioridad.
    // llama-3.1-8b-instant está disponible en todas las cuentas (incluyendo Free/Developer).
    final candidateModels = <String>{
      if (preferredModel != null && preferredModel.trim().isNotEmpty) preferredModel.trim(),
      'llama-3.1-8b-instant',
      'llama-3.3-70b-versatile',
      'openai/gpt-oss-120b',
    }.toList();

    String lastError = '';

    for (final model in candidateModels) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': temperature,
          }),
        );

        if (response.statusCode == 200) {
          final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
          final content = jsonResponse['choices']?[0]?['message']?['content'];
          if (content != null && content is String) {
            return content;
          }
        }

        // Si el modelo no existe o la cuenta no tiene acceso (404), intentamos con el siguiente modelo
        if (response.statusCode == 404) {
          lastError = "El modelo '$model' no está disponible en la cuenta configurada.";
          continue;
        }

        if (response.statusCode == 401) {
          return "Error de autenticación con la IA: La API Key configurada no es válida.";
        } else if (response.statusCode == 429) {
          return "Límite de solicitudes alcanzado en la IA. Por favor, intenta de nuevo en unos momentos.";
        } else {
          lastError = "Error en la IA (${response.statusCode}): ${response.body}";
        }
      } catch (e) {
        lastError = "Error de conexión con la IA: $e";
      }
    }

    return lastError.isNotEmpty
        ? lastError
        : "No fue posible generar la respuesta de la IA.";
  }

  Future<String> analyzeRouteProfitability(List<RouteProfitability> data) async {
    try {
      final config = await _getAiConfig();

      // Preparar los datos
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

      return await _callGroqChat(
        apiKey: config.apiKey,
        preferredModel: config.model,
        messages: [
          {'role': 'system', 'content': 'Eres un asistente experto en analítica de transporte.'},
          {'role': 'user', 'content': prompt}
        ],
        temperature: 0.7,
      );
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
      final config = await _getAiConfig();

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

      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': systemPrompt},
        ...history,
        {'role': 'user', 'content': question},
      ];

      return await _callGroqChat(
        apiKey: config.apiKey,
        preferredModel: config.model,
        messages: messages,
        temperature: 0.3, // Menos creativo, más preciso
      );
    } catch (e) {
      return "Error de conexión: $e";
    }
  }

  /// Consulta libre sobre la flota usando datos reales de Firestore.
  /// La IA recibe RESÚMENES compactos, no coordenadas brutas.
  /// Solo se llama cuando el usuario lo pide explícitamente.
  Future<String> askFleetOperations({
    required String question,
    required String idEmpresa,
    String? plate,
    List<Map<String, String>> history = const [],
  }) async {
    try {
      final config = await _getAiConfig();
      final harvest = GpsHarvestService();

      // Cargar contexto desde Firestore (resúmenes compactos, ~100 tokens cada uno)
      final tripSummaries = await harvest.getRecentTripSummariesForAi(
        empresa: idEmpresa,
        plate: plate,
        limit: 15, // últimos 15 viajes
      );
      final recentEvents = await harvest.getRecentEventsForAi(
        empresa: idEmpresa,
        plate: plate,
        limit: 20,
      );
      final stats = await harvest.getFleetStats(empresa: idEmpresa);

      // Construir bloque de contexto compacto
      final contextBlock = StringBuffer();
      contextBlock.writeln('=== ESTADÍSTICAS GLOBALES ===');
      if (stats.isNotEmpty) {
        stats.forEach((k, v) => contextBlock.writeln('$k: $v'));
      } else {
        contextBlock.writeln('(aún no hay suficientes datos recopilados)');
      }

      contextBlock.writeln('\n=== ÚLTIMOS VIAJES (resumidos) ===');
      if (tripSummaries.isEmpty) {
        contextBlock.writeln('(no hay viajes registrados aún)');
      } else {
        for (final s in tripSummaries) {
          contextBlock.writeln('• $s');
        }
      }

      contextBlock.writeln('\n=== EVENTOS RECIENTES ===');
      if (recentEvents.isEmpty) {
        contextBlock.writeln('(no hay eventos registrados aún)');
      } else {
        for (final e in recentEvents) {
          contextBlock.writeln('• $e');
        }
      }

      final systemPrompt = '''
Eres "Bitácora AI", Asistente Operacional de flota de transporte.

CONTEXTO REAL DE LA OPERACIÓN (datos de telemetría GPS de Firestore):
${contextBlock.toString()}

REGLAS:
1. Basa tus respuestas ÚNICAMENTE en los datos de contexto anteriores.
2. Si los datos son insuficientes, indícalo claramente.
3. Solo responde temas de logística, transporte, flota y operaciones.
4. Sé conciso, profesional y usa bullets cuando sea útil.
5. Nunca inventes datos que no estén en el contexto.
''';

      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': systemPrompt},
        ...history,
        {'role': 'user', 'content': question},
      ];

      return await _callGroqChat(
        apiKey: config.apiKey,
        preferredModel: config.model,
        messages: messages,
        temperature: 0.2, // Muy determinístico — datos reales
      );
    } catch (e) {
      return 'Error al consultar datos de flota: $e';
    }
  }
}
