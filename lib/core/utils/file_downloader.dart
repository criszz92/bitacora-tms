import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

void downloadCsvFile(String filename, String content) {
  final bytes = utf8.encode(content);
  if (kIsWeb) {
    // En Web, Printing.sharePdf comparte los bytes y activa la descarga del navegador nativamente
    Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: filename,
    );
  } else {
    Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: filename,
    );
  }
}

