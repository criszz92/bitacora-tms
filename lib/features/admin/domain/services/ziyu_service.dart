import 'dart:convert';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:csv/csv.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/ziyu_models.dart';
import '../../../trips/domain/models/trip_model.dart';

/// Servicio central de conciliación Ziyu.
/// 
/// Mejorado para usar SpreadsheetDecoder (más robusto) y soportar CSV.
class ZiyuService {
  
  /// Parsea un archivo (Excel o CSV) y retorna la lista de registros Ziyu.
  /// Parsea un archivo (Excel, CSV o PDF) y retorna la lista de registros.
  static List<ZiyuRecord> parseFile(List<int> bytes, String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.csv')) {
      return _parseCsv(bytes);
    } else if (name.endsWith('.pdf')) {
      return _parsePdf(bytes);
    } else {
      return _parseExcel(bytes);
    }
  }

  // ─── Parseo de Excel ────────────────────────────────────────────────────────

  static List<ZiyuRecord> _parseExcel(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);
    final records = <ZiyuRecord>[];

    for (final sheetName in decoder.tables.keys) {
      final table = decoder.tables[sheetName]!;
      if (table.rows.isEmpty) continue;

      final headerRow = _findHeaderRow(table.rows);
      if (headerRow == null) continue;

      final colMap = _detectColumns(headerRow);
      final headerIdx = table.rows.indexOf(headerRow);

      for (int i = headerIdx + 1; i < table.rows.length; i++) {
        final row = table.rows[i];
        if (_isEmptyRow(row)) continue;

        final record = _parseRow(row, colMap, i + 1);
        if (record != null) records.add(record);
      }
      break; // Solo procesar la primera hoja con datos
    }

    if (records.isEmpty) {
      throw Exception('No se detectaron columnas compatibles en el Excel. Intenta asegurar que tenga encabezados como "Contenedor", "Guía" o "Valor".');
    }
    return records;
  }

  // ─── Parseo de CSV ──────────────────────────────────────────────────────────

  static List<ZiyuRecord> _parseCsv(List<int> bytes) {
    final csvString = utf8.decode(bytes, allowMalformed: true);
    final rows = const CsvToListConverter(
      fieldDelimiter: ';', // Común en Excels latinos
      shouldParseNumbers: false,
    ).convert(csvString);

    // Si no detecta columnas con ';', probar con ','
    if (rows.isNotEmpty && rows[0].length < 2) {
       final rowsComma = const CsvToListConverter(
        fieldDelimiter: ',',
        shouldParseNumbers: false,
      ).convert(csvString);
      if (rowsComma.isNotEmpty && rowsComma[0].length > rows[0].length) {
        return _processRows(rowsComma);
      }
    }

    return _processRows(rows);
  }

  static List<ZiyuRecord> _processRows(List<List<dynamic>> rows) {
    final records = <ZiyuRecord>[];
    final headerRow = _findHeaderRow(rows);
    if (headerRow == null) return [];

    final colMap = _detectColumns(headerRow);
    final headerIdx = rows.indexOf(headerRow);

    for (int i = headerIdx + 1; i < rows.length; i++) {
      final row = rows[i];
      if (_isEmptyRow(row)) continue;

      final record = _parseRow(row, colMap, i + 1);
      if (record != null) records.add(record);
    }
    if (records.isEmpty) {
      throw Exception('No se detectaron columnas compatibles en el archivo. Intenta asegurar que tenga encabezados válidos.');
    }
    return records;
  }

  // ─── Parseo de PDF (Experimental) ──────────────────────────────────────────

  static List<ZiyuRecord> _parsePdf(List<int> bytes) {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final String text = PdfTextExtractor(document).extractText();
      document.dispose();
      
      final records = <ZiyuRecord>[];
      
      // 1. Buscar Contenedores (4 letras + 7 dígitos)
      final containerRegex = RegExp(r'\b([A-Z]{4}[0-9]{7})\b');
      final containers = containerRegex.allMatches(text).map((m) => m.group(1)!).toSet();
      
      // 2. Buscar números que parezcan guías (6 a 10 dígitos)
      final guideRegex = RegExp(r'\b([0-9]{6,10})\b');
      final guides = guideRegex.allMatches(text).map((m) => m.group(1)!).toSet();

      // 3. Buscar Montos (formato CLP: 100.000 o similar)
      final valueRegex = RegExp(r'([0-9]{1,3}(\.[0-9]{3}){1,2})'); 
      final allValues = valueRegex.allMatches(text).map((m) => m.group(1)!.replaceAll('.', '')).toList();

      // Intentar crear registros basados en contenedores encontrados
      for (final container in containers) {
        double? foundValue;
        if (allValues.isNotEmpty) {
           // Tomamos el valor más alto o el primero como heurística simple
           foundValue = double.tryParse(allValues.first);
        }
        
        records.add(ZiyuRecord(
          rowIndex: 0,
          containerNumber: container,
          value: foundValue,
          rawData: 'Documento PDF | Contenedor: $container',
        ));
      }

      // Si no hay contenedores, intentar con guías
      if (records.isEmpty) {
        for (final guide in guides) {
          records.add(ZiyuRecord(
            rowIndex: 0,
            guideNumber: guide,
            rawData: 'Documento PDF | Guía: $guide',
          ));
        }
      }
      
      if (records.isEmpty) {
        throw Exception('No se detectaron identificadores (contenedores o guías) legibles en el PDF.');
      }
      
      return records;
    } catch (e) {
      throw Exception('Error al leer el PDF: $e');
    }
  }

  // ─── Lógica Compartida ──────────────────────────────────────────────────────

  static List<dynamic>? _findHeaderRow(List<List<dynamic>> rows) {
    const keywords = [
      'contenedor', 'container', 'cntr', 'equipo',
      'os', 'nro os', 'orden',
      'guia', 'guía', 'bl', 'documento',
      'origen', 'retiro',
      'destino', 'entrega',
      'cliente', 'mandante', 'empresa', 'razon', 'rut',
      'valor', 'monto', 'precio', 'tarifa', 'neto', 'total',
      'fecha', 'date', 'servicio', 'creacion',
      'patente', 'camion', 'camión', 'placa', 'vehiculo', 'tracto'
    ];

    List<dynamic>? bestRow;
    int maxScore = 0;

    for (final row in rows.take(100)) {
      int score = 0;
      for (final cell in row) {
        if (cell == null) continue;
        final text = cell.toString().toLowerCase().trim();
        if (text.length > 40) continue; // Un cabezal de tabla no suele ser un texto gigante

        if (_matches(text, keywords)) {
          score++;
        }
      }

      if (score > maxScore) {
        maxScore = score;
        bestRow = row;
      }
    }

    if (maxScore >= 3) {
      return bestRow;
    }
    return null;
  }

  static Map<String, int> _detectColumns(List<dynamic> headerRow) {
    final colMap = <String, int>{};

    for (int i = 0; i < headerRow.length; i++) {
      final cell = headerRow[i];
      if (cell == null) continue;
      final text = cell.toString().toLowerCase().trim();
      if (text.isEmpty) continue;

      if (_matches(text, ['contenedor', 'container', 'cntr', 'equipo'])) {
        colMap['container'] = i;
      } else if (_matches(text, ['os', 'orden', 'nro os', 'n° os', 'n° orden'])) {
        colMap['os'] = i;
      } else if (_matches(text, ['guia', 'guía', 'bl', 'n° guia', 'documento'])) {
        colMap['guide'] = i;
      } else if (_matches(text, ['origen', 'puerto origen', 'from', 'retiro'])) {
        colMap['origin'] = i;
      } else if (_matches(text, ['destino', 'puerto destino', 'to', 'entrega'])) {
        colMap['destination'] = i;
      } else if (_matches(text, ['cliente', 'mandante', 'empresa', 'razon', 'rut'])) {
        colMap['client'] = i;
      } else if (_matches(text, ['valor', 'monto', 'precio', 'tarifa', 'amount', 'total', 'neto'])) {
        colMap['value'] = i;
      } else if (_matches(text, ['fecha', 'date', 'dia', 'servicio', 'creacion'])) {
        colMap['date'] = i;
      } else if (_matches(text, ['patente', 'camion', 'camión', 'placa', 'vehiculo', 'vehicle', 'tracto'])) {
        colMap['plate'] = i;
      }
    }
    return colMap;
  }

  static bool _matches(String text, List<String> keywords) {
    return keywords.any((k) {
      if (k.length <= 3) {
        // Para palabras cortas como 'os', 'bl', 'to', 'rut', 'dia' exigimos que sea la palabra completa o termine/empiece con ella
        // Esto evita que "costos" coincida con "os", o "pueblo" coincida con "bl"
        final regex = RegExp(r'\b' + k + r'\b');
        return regex.hasMatch(text);
      }
      return text.contains(k);
    });
  }

  static ZiyuRecord? _parseRow(List<dynamic> row, Map<String, int> colMap, int rowIndex) {
    String? getCell(String key) {
      final idx = colMap[key];
      if (idx == null || idx >= row.length || row[idx] == null) return null;
      return row[idx].toString().trim();
    }

    final rawData = row.map((c) => c?.toString() ?? '').join(' | ');

    final container = getCell('container');
    final os = getCell('os');
    final guide = getCell('guide');
    if (container == null && os == null && guide == null) return null;

    double? value;
    final valueStr = getCell('value');
    if (valueStr != null) {
      value = double.tryParse(
        valueStr.replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.'),
      );
    }

    DateTime? date;
    final dateStr = getCell('date');
    if (dateStr != null) {
      date = DateTime.tryParse(dateStr);
      if (date == null) {
        // Intento manual para formato DD/MM/YYYY común en Chile
        try {
          final parts = dateStr.split('/');
          if (parts.length == 3) {
            date = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        } catch (_) {}
      }
    }

    return ZiyuRecord(
      rowIndex: rowIndex,
      osNumber: os,
      containerNumber: container,
      guideNumber: guide,
      origin: getCell('origin'),
      destination: getCell('destination'),
      client: getCell('client'),
      value: value,
      date: date,
      vehiclePlate: getCell('plate'),
      rawData: rawData,
    );
  }

  static bool _isEmptyRow(List<dynamic> row) =>
      row.every((c) => c == null || c.toString().trim().isEmpty);

  // ─── Motor de Conciliación (Misma lógica anterior) ──────────────────────────

  static List<ReconciliationResult> reconcile({
    required List<ZiyuRecord> ziyuRecords,
    required List<TripModel> bitacoraTrips,
  }) {
    final results = <ReconciliationResult>[];
    final osBitacoraTrips = bitacoraTrips
        .where((t) => t.billingType == 'OS' && t.status != 'En Ruta')
        .toList();

    final matchedTripIds = <String>{};

    for (final ziyu in ziyuRecords) {
      TripModel? match;
      String matchKey = '';

      for (final trip in osBitacoraTrips) {
        if (matchedTripIds.contains(trip.id)) continue;
        
        // 1. MATCH: Contenedor
        if (ZiyuRecord.isSmartMatch(ziyu.containerNumber ?? '', trip.containerNumber ?? '')) {
          match = trip;
          matchKey = 'Contenedor: ${ziyu.containerNumber}';
          break;
        }

        // 2. MATCH: Guía
        if (ZiyuRecord.isSmartMatch(ziyu.guideNumber ?? '', trip.guideNumber ?? '')) {
          match = trip;
          matchKey = 'Guía: ${ziyu.guideNumber}';
          break;
        }

        // 3. SMART MATCH: Contenedor Excel -> Guía App
        if (ZiyuRecord.isSmartMatch(ziyu.containerNumber ?? '', trip.guideNumber ?? '')) {
          match = trip;
          matchKey = 'Smart (Contenedor -> Guía): ${ziyu.containerNumber}';
          break;
        }

        // 4. SMART MATCH: Guía Excel -> Contenedor App
        if (ZiyuRecord.isSmartMatch(ziyu.guideNumber ?? '', trip.containerNumber ?? '')) {
          match = trip;
          matchKey = 'Smart (Guía -> Contenedor): ${ziyu.guideNumber}';
          break;
        }

        // 5. SMART MATCH: OS Excel -> Guía/Contenedor App
        if (ziyu.osNumber != null) {
          if (ZiyuRecord.isSmartMatch(ziyu.osNumber!, trip.guideNumber ?? '')) {
            match = trip;
            matchKey = 'Smart (OS -> Guía): ${ziyu.osNumber}';
            break;
          }
          if (ZiyuRecord.isSmartMatch(ziyu.osNumber!, trip.containerNumber ?? '')) {
            match = trip;
            matchKey = 'Smart (OS -> Contenedor): ${ziyu.osNumber}';
            break;
          }
        }
      }

      if (match != null) {
        matchedTripIds.add(match.id);
        final ziyuVal = ziyu.value;
        final diferencia = ziyuVal != null ? (match.value - ziyuVal) : null;
        
        // VALIDACIÓN DE PATENTE: El corazón del desafío "Reloj Suizo"
        bool plateMismatch = false;
        if (ziyu.normalizedPlate.isNotEmpty && match.vehicleId != null) {
           final normalizedTripPlate = ZiyuRecord.normalize(match.vehicleId!);
           if (ziyu.normalizedPlate != normalizedTripPlate) {
             plateMismatch = true;
           }
        }

        results.add(ReconciliationResult(
          status: plateMismatch ? ReconciliationStatus.warningPlate : ReconciliationStatus.matched,
          ziyuRecord: ziyu,
          tripModel: match,
          matchKey: matchKey,
          diferencia: diferencia,
        ));
      } else {
        String matchKey = ziyu.containerNumber ?? '';
        if (matchKey.isEmpty) matchKey = ziyu.guideNumber ?? '';
        if (matchKey.isEmpty) matchKey = ziyu.osNumber ?? '';
        if (matchKey.isEmpty) matchKey = 'Fila ${ziyu.rowIndex}';

        results.add(ReconciliationResult(
          status: ReconciliationStatus.onlyInZiyu,
          ziyuRecord: ziyu,
          matchKey: matchKey,
        ));
      }
    }

    for (final trip in osBitacoraTrips) {
      if (!matchedTripIds.contains(trip.id)) {
        String matchKey = trip.containerNumber ?? '';
        if (matchKey.isEmpty) matchKey = trip.guideNumber ?? '';
        if (matchKey.isEmpty) matchKey = 'Sin ID';

        results.add(ReconciliationResult(
          status: ReconciliationStatus.onlyInBitacora,
          tripModel: trip,
          matchKey: matchKey,
        ));
      }
    }

    results.sort((a, b) => a.status.index.compareTo(b.status.index));
    return results;
  }

  static Map<String, int> summarize(List<ReconciliationResult> results) {
    return {
      'total': results.length,
      'matched': results.where((r) => r.status == ReconciliationStatus.matched).length,
      'onlyZiyu': results.where((r) => r.status == ReconciliationStatus.onlyInZiyu).length,
      'onlyBitacora': results.where((r) => r.status == ReconciliationStatus.onlyInBitacora).length,
    };
  }
}
