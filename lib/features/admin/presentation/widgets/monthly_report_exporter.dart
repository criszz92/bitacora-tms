import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../domain/models/company_config_model.dart';
import '../../domain/models/incidencia_model.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../trips/domain/models/expense_model.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../../../core/utils/chilean_holidays.dart';
import '../../../../core/utils/number_utils.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class MonthlyReportExporter {
  /// Genera y descarga el PDF Ejecutivo Oficial Multipágina del Mes
  static Future<void> exportMonthlyReportPdf({
    required DateTime selectedMonth,
    required CompanyConfigModel config,
    required Map<String, double> summary,
    required List<TripModel> monthlyTrips,
    required List<ExpenseModel> monthlyExpenses,
    required List<VehicleModel> vehicles,
    required List<IncidenciaModel> incidencias,
    required List<UserModel> drivers,
    required List<Map<String, dynamic>> routeStats,
    required List<Map<String, dynamic>> vehicleStats,
    required List<Map<String, dynamic>> history3Months,
  }) async {
    final pdf = pw.Document();
    final fmt = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);
    final monthName = DateFormat('MMMM yyyy', 'es_CL').format(selectedMonth).toUpperCase();

    // ─── PÁGINA 1: PORTADA Y RESUMEN EJECUTIVO (LOS 3 BLOQUES Y F29) ───
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Encabezado
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('HEIRLOG-TMS', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
                    pw.Text(config.emisorRazonSocial.isNotEmpty ? config.emisorRazonSocial : 'INFORME FINANCIERO & OPERACIONAL MENSUAL',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                    if (config.emisorRut.isNotEmpty)
                      pw.Text('RUT: ${config.emisorRut} | Giro: ${config.emisorGiro}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.orange50,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: PdfColors.orange300),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('PERIODO AUDITADO', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                      pw.Text(monthName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(color: PdfColors.grey400, thickness: 1),
            pw.SizedBox(height: 12),

            // Tarjetas Superiores de Métricas
            pw.Row(
              children: [
                _buildPdfCard('Total Viajes', '${summary['totalViajes']?.toInt() ?? monthlyTrips.length}', PdfColors.blue50),
                pw.SizedBox(width: 8),
                _buildPdfCard('KM Flota', '${NumberUtils.formatCurrency(summary['totalKmFlota'] ?? 0)} KM', PdfColors.purple50),
                pw.SizedBox(width: 8),
                _buildPdfCard('Margen Op. (EBITDA)', '${(summary['margenOperacional'] ?? 0).toStringAsFixed(1)}%', PdfColors.green50),
                pw.SizedBox(width: 8),
                _buildPdfCard('Disp. Libre Caja', fmt.format(summary['flujoCajaReal'] ?? 0), PdfColors.amber50),
              ],
            ),
            pw.SizedBox(height: 16),

            // Tablas de los 3 Bloques
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Bloque 1: Operación Pura
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('1. RESULTADO OPERATIVO (P&L)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.SizedBox(height: 6),
                        _pdfRow('Facturación Neta:', fmt.format(summary['ingresosNetos'] ?? 0)),
                        _pdfRow('(-) Gastos Operativos:', fmt.format(-(summary['gastosNetos'] ?? 0))),
                        _pdfRow('(-) Costos de Personal:', fmt.format(-(summary['costosPersonal'] ?? 0))),
                        pw.Divider(color: PdfColors.grey300),
                        _pdfRow('MARGEN OPERACIONAL:', fmt.format(summary['resultadoOperacional'] ?? 0), isBold: true),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),

                // Bloque 2: Radiografía F29
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('2. RADIOGRAFÍA TRIBUTARIA F29', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                        pw.SizedBox(height: 6),
                        _pdfRow('IVA Débito (19%):', fmt.format(summary['ivaDebito'] ?? 0)),
                        _pdfRow('(-) IVA Crédito Compras:', fmt.format(-(summary['ivaCredito'] ?? 0))),
                        _pdfRow('(-) Ley 19.764 Diésel:', fmt.format(-(summary['recuperacionDiesel'] ?? 0))),
                        if ((summary['remanenteAnterior'] ?? 0) > 0)
                          _pdfRow('(-) Remanente Anterior:', fmt.format(-(summary['remanenteAnterior'] ?? 0))),
                        _pdfRow('(+) PPM Obligatorio:', fmt.format(summary['ppmObligatorio'] ?? 0)),
                        pw.Divider(color: PdfColors.grey300),
                        _pdfRow('F29 DÍA 20 A PAGAR:', fmt.format(summary['totalF29Pagar'] ?? 0), isBold: true),
                        if ((summary['nuevoRemanenteFavor'] ?? 0) > 0)
                          _pdfRow('⭐ Remanente Mes Sig.:', fmt.format(summary['nuevoRemanenteFavor'] ?? 0), isBold: true),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),

                // Bloque 3: Caja Bancaria
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('3. CONCILIACIÓN DE CAJA REAL', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                        pw.SizedBox(height: 6),
                        _pdfRow('Cobrado Bruto:', fmt.format(summary['ingresosBrutos'] ?? 0)),
                        _pdfRow('(-) Desembolsos Brutos:', fmt.format(-(summary['gastosBrutos'] ?? 0))),
                        _pdfRow('(-) Sueldos / Leyes:', fmt.format(-(summary['costosPersonal'] ?? 0))),
                        _pdfRow('(-) F29 día 20:', fmt.format(-(summary['totalF29Pagar'] ?? 0))),
                        pw.Divider(color: PdfColors.grey300),
                        _pdfRow('DISP. CON IVA:', fmt.format(summary['flujoCajaReal'] ?? 0), isBold: true),
                        _pdfRow('DISP. SIN IVA:', fmt.format(summary['flujoCajaSinIva'] ?? 0), isBold: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 16),

            // Comparativa Trimestral Histórica
            pw.Text('COMPARATIVA HISTÓRICA RECIENTE (ÚLTIMOS MESES)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Mes', 'Viajes', 'Facturación Neta', 'Gastos Totales', 'Margen Operacional', 'F29 Pagado', 'Caja Libre'],
              data: history3Months.map((h) => [
                h['mesLabel'],
                '${h['viajes']}',
                fmt.format(h['ingresosNetos']),
                fmt.format(h['gastosBrutos']),
                fmt.format(h['resultadoOperacional']),
                fmt.format(h['f29']),
                fmt.format(h['flujoCajaReal']),
              ]).toList(),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            ),

            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Página 1 de 2 | Sistema de Gestión Bitácora TMS', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                pw.Text('Generado el ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
              ],
            ),
          ],
        ),
      ),
    );

    // ─── PÁGINA 2: RENDIMIENTO POR CAMIÓN, DÍAS EN TALLER Y RUTAS ───
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('RADIOGRAFÍA POR UNIDAD / CAMIÓN (DISPONIBILIDAD Y COSTO)', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
            pw.SizedBox(height: 8),

            // Tabla de Unidades
            pw.TableHelper.fromTextArray(
              headers: ['Patente', 'KM Recorridos', 'Viajes', 'Litros', 'Rend. Km/L', 'Días Taller', 'Disp. Flota %', 'Gasto Real Taller', 'Desgaste Teórico'],
              data: vehicleStats.map((v) => [
                v['patente'],
                '${NumberUtils.formatCurrency(v['km'])} KM',
                '${v['viajes']}',
                '${v['litros']?.toStringAsFixed(0)} L',
                '${v['rendimiento']?.toStringAsFixed(2)}',
                '${v['diasTaller']} días',
                '${(v['tasaDisponibilidad'] as double).toStringAsFixed(1)}%',
                fmt.format(v['gastoTallerReal']),
                fmt.format(v['desgasteTeorico']),
              ]).toList(),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.orange900),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            ),

            pw.SizedBox(height: 16),
            pw.Text('MATRIZ DE RENTABILIDAD POR RUTA Y CLIENTES', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
            pw.SizedBox(height: 8),

            // Tabla de Rutas
            pw.TableHelper.fromTextArray(
              headers: ['Ruta (Origen -> Destino)', 'Vueltas', 'Facturación Neta', 'Costos Directos', 'Margen Bruto', 'Rentabilidad %'],
              data: routeStats.map((r) => [
                r['ruta'],
                '${r['frecuencia']}',
                fmt.format(r['ingreso']),
                fmt.format(r['costo']),
                fmt.format(r['margen']),
                '${(r['rentabilidad'] as double).toStringAsFixed(1)}%',
              ]).toList(),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            ),

            pw.SizedBox(height: 16),
            pw.Text('INCIDENCIAS Y MANTENCIONES EN TALLER REGISTRADAS EN EL MES', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
            pw.SizedBox(height: 8),

            // Tabla de Incidencias
            pw.TableHelper.fromTextArray(
              headers: ['Fecha', 'Patente', 'Tipo', 'Descripción / Trabajo', 'Proveedor Taller', 'Días Detenido', 'Costo Factura'],
              data: incidencias.where((i) {
                final d = i.fecha;
                return d.year == selectedMonth.year && d.month == selectedMonth.month;
              }).map((i) {
                final dias = ChileanHolidays.getDiasDetenidosHabiles(i.fechaIngresoTaller ?? i.fecha, i.fechaResolucion);
                return [
                  DateFormat('dd/MM/yyyy').format(i.fecha),
                  i.vehiclePatente,
                  i.tipo,
                  i.descripcion,
                  i.tallerProveedor ?? 'N/A',
                  '$dias días',
                  i.costoReparacion != null ? fmt.format(i.costoReparacion) : 'Sin costo',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.red900),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            ),

            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Página 2 de 2 | Sistema de Gestión Bitácora TMS', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                pw.Text('Certificación Fuente de Verdad', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
              ],
            ),
          ],
        ),
      ),
    );

    // Descarga o impresión en navegador Web
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Informe_Mensual_${selectedMonth.year}_${selectedMonth.month}.pdf',
    );
  }

  /// Exporta el archivo estructurado para Microsoft Excel / Google Sheets en formato CSV delimitado por punto y coma
  static void exportMonthlyReportExcel({
    required DateTime selectedMonth,
    required CompanyConfigModel config,
    required Map<String, double> summary,
    required List<TripModel> monthlyTrips,
    required List<ExpenseModel> monthlyExpenses,
    required List<VehicleModel> vehicles,
    required List<IncidenciaModel> incidencias,
    required List<UserModel> drivers,
    required List<Map<String, dynamic>> routeStats,
    required List<Map<String, dynamic>> vehicleStats,
  }) {
    final sb = StringBuffer();
    // Añadimos UTF-8 BOM para que Microsoft Excel en Windows lo abra perfecto con tildes y símbolos
    sb.write('\uFEFF');

    sb.writeln('INFORME MENSUAL AUDITADO - BITACORA TMS;Periodo:;${DateFormat('MMMM yyyy', 'es_CL').format(selectedMonth).toUpperCase()}');
    sb.writeln('Empresa:;${config.emisorRazonSocial};RUT:;${config.emisorRut}');
    sb.writeln('');

    // BLOQUE FINANCIERO
    sb.writeln('=== RESUMEN FINANCIERO (P&L Y TRIBUTARIO) ===');
    sb.writeln('Concepto;Monto (CLP);Notas');
    sb.writeln('Facturación Neta Fletes;${summary['ingresosNetos']?.toInt() ?? 0};Ingreso operacional puro');
    sb.writeln('(-) Gastos Operacionales Netos;${-(summary['gastosNetos']?.toInt() ?? 0)};Combustible y otros netos + peajes');
    sb.writeln('(-) Costos de Personal (Haberes+Leyes);${-(summary['costosPersonal']?.toInt() ?? 0)};Sueldos e imposiciones');
    sb.writeln('MARGEN OPERACIONAL (EBITDA);${summary['resultadoOperacional']?.toInt() ?? 0};Margen %: ${(summary['margenOperacional'] ?? 0).toStringAsFixed(1)}%');
    sb.writeln('IVA Débito Fiscal (19%);${summary['ivaDebito']?.toInt() ?? 0};IVA ventas');
    sb.writeln('(-) IVA Crédito Compras;${-(summary['ivaCredito']?.toInt() ?? 0)};IVA facturas gastos');
    sb.writeln('(-) Beneficio Ley 19.764 Diésel;${-(summary['recuperacionDiesel']?.toInt() ?? 0)};Recuperación IEPD');
    sb.writeln('(-) Remanente IVA Anterior;${-(summary['remanenteAnterior']?.toInt() ?? 0)};Saldo a favor anterior');
    sb.writeln('(+) PPM Obligatorio;${summary['ppmObligatorio']?.toInt() ?? 0};Pago provisional');
    sb.writeln('TOTAL A PAGAR F29 (DÍA 20);${summary['totalF29Pagar']?.toInt() ?? 0};Obligación tributaria');
    sb.writeln('⭐ Remanente a Favor Mes Siguiente;${summary['nuevoRemanenteFavor']?.toInt() ?? 0};Pasa al próximo mes');
    sb.writeln('Disponible Caja Banco (CON IVA);${summary['flujoCajaReal']?.toInt() ?? 0};Dinero real en cuenta');
    sb.writeln('Disponible Caja Banco (SIN IVA);${summary['flujoCajaSinIva']?.toInt() ?? 0};Operación neta pura');
    sb.writeln('');

    // TABLA POR CAMIÓN
    sb.writeln('=== RADIOGRAFÍA DE LA FLOTA Y DÍAS DETENIDO ===');
    sb.writeln('Patente;Marca;KM Recorridos;Viajes;Litros Diésel;Km/Litro;Días Taller (Lun-Sáb);Tasa Disponibilidad %;Gasto Real Taller;Desgaste Teórico');
    for (final v in vehicleStats) {
      sb.writeln('${v['patente']};${v['marca']};${v['km']};${v['viajes']};${v['litros']};${v['rendimiento']};${v['diasTaller']};${(v['tasaDisponibilidad'] as double).toStringAsFixed(1)}%;${v['gastoTallerReal']};${v['desgasteTeorico']}');
    }
    sb.writeln('');

    // TABLA DE RUTAS
    sb.writeln('=== MATRIZ DE RENTABILIDAD POR RUTA ===');
    sb.writeln('Ruta;Frecuencia;Ingreso Neto;Costo Directo;Margen Bruto;Rentabilidad %');
    for (final r in routeStats) {
      sb.writeln('${r['ruta']};${r['frecuencia']};${r['ingreso']};${r['costo']};${r['margen']};${(r['rentabilidad'] as double).toStringAsFixed(1)}%');
    }
    sb.writeln('');

    // LISTADO DE VIAJES DETALLADOS
    sb.writeln('=== DETALLE DE VIAJES DEL MES ===');
    sb.writeln('ID;Fecha;Origen;Destino;Patente;Conductor;Cliente;Guía;KM;Valor Neto;Extras;Sobre-estadía;Total');
    for (final t in monthlyTrips) {
      final total = t.value + (t.extraCostos ?? 0) + (t.sobreEstadia ?? 0);
      sb.writeln('${t.id};${DateFormat('dd/MM/yyyy').format(t.startDate)};${t.origin};${t.destination};${t.vehicleId ?? "N/A"};${(drivers.where((d) => d.uid == t.idChofer).firstOrNull?.nombre ?? 'Chofer')};${t.client};${t.guideNumber ?? ""};${t.totalKm ?? 0};${t.value};${t.extraCostos ?? 0};${t.sobreEstadia ?? 0};$total');
    }

    final bytes = utf8.encode(sb.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'Informe_Mensual_${selectedMonth.year}_${selectedMonth.month}.csv')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static pw.Widget _buildPdfCard(String title, String val, PdfColor bg) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text(val, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pdfRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 7.5, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(fontSize: 7.5, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }
}
