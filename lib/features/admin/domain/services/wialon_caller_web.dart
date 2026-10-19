import 'dart:convert';
import 'dart:js_interop';

@JS('wialonJsonp')
external JSPromise<JSString> _wialonJsonp(JSString url);

Future<Map<String, dynamic>> callWialon(String url) async {
  final promise = _wialonJsonp(url.toJS);
  final jsStr = await promise.toDart;
  final decoded = jsonDecode(jsStr.toDart);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  throw Exception('Respuesta inesperada de Wialon');
}
