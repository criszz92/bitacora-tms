import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> callWialon(String url) async {
  final res = await http.get(Uri.parse(url));
  if (res.statusCode == 200) {
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  }
  throw Exception('Error en respuesta Wialon (${res.statusCode})');
}
