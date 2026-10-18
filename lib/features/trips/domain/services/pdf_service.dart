import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/trip_model.dart';
import '../../../auth/domain/models/user_model.dart';
import 'package:bitacora/features/admin/domain/models/company_config_model.dart';

class PdfService {
  static Future<void> generateAndShareViaticosPdf(
    UserModel user, 
    DateTime start, 
    DateTime end, 
    List<TripModel> trips,
    CompanyConfigModel config,
  ) async {
    final pdf = pw.Document();
    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);
    
    // Preparar datos
    final Map<String, List<TripModel>> tripsByDay = {};
    for (final t in trips) {
      final dayKey = '${t.startDate.year}-${t.startDate.month}-${t.startDate.day}';
      tripsByDay.putIfAbsent(dayKey, () => []).add(t);
    }

    double total = 0;
    for (final dayTrips in tripsByDay.values) {
      bool existsLongTrip = dayTrips.any((t) => (t.totalKm ?? 0.0) >= config.umbralKilometrosViatico);
      total += existsLongTrip ? (user.montoViaticoLargo ?? 10000) : (user.montoViaticoLocal ?? 6500);
    }
    
    final periodStr = '${start.day}/${start.month}/${start.year} al ${end.day}/${end.month}/${end.year}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // HEADER
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('HEIRLOG-TMS', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Rendición de Viáticos', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text('Período: $periodStr', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            // CONDUCTOR INFO
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Conductor: ${user.nombre}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text('Empresa ID: ${user.idEmpresa}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 30),

            // RESUMEN KPI
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildKpiCard('Total Viajes', '${trips.length}'),
                _buildKpiCard('Total Días Rendidos', '${tripsByDay.length}'),
                _buildKpiCard('Total a Pagar', currency.format(total), color: PdfColors.green100),
              ],
            ),
            pw.SizedBox(height: 30),

            // DETALLE DE VIAJES
            pw.Text('Detalle de Viajes Realizados', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            if (trips.isEmpty)
               pw.Text('No hay viajes registrados en este periodo.', style: const pw.TextStyle(fontSize: 14))
            else
                pw.TableHelper.fromTextArray(
                  context: context,
                  headers: ['Fecha', 'Ruta', 'Patente', 'KM', 'Tipo', 'Monto Asignado'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  cellAlignment: pw.Alignment.centerLeft,
                  data: () {
                    final List<List<String>> rows = [];
                    final Map<String, bool> dayHasPaid = {};
                    
                    // Asegurarnos de que los viajes estén ordenados cronológicamente
                    final sortedTrips = List<TripModel>.from(trips)
                      ..sort((a, b) => a.startDate.compareTo(b.startDate));
                      
                    for (var t in sortedTrips) {
                      final km = t.totalKm ?? 0.0;
                      final isLong = km >= config.umbralKilometrosViatico;
                      final dayKey = '${t.startDate.year}-${t.startDate.month}-${t.startDate.day}';
                      String montoStr = '';
                      
                      // Forzamos POR_JORNADA siempre como regla de negocio
                      if (dayHasPaid.containsKey(dayKey)) {
                        montoStr = 'Incluido en Jornada';
                      } else {
                        final dayTrips = sortedTrips.where((tri) => 
                          '${tri.startDate.year}-${tri.startDate.month}-${tri.startDate.day}' == dayKey).toList();
                        final hasLong = dayTrips.any((tri) => (tri.totalKm ?? 0) >= config.umbralKilometrosViatico);
                        final monto = hasLong ? (user.montoViaticoLargo ?? 10000) : (user.montoViaticoLocal ?? 6500);
                        montoStr = currency.format(monto);
                        dayHasPaid[dayKey] = true;
                      }

                      rows.add([
                        '${t.startDate.day}/${t.startDate.month}/${t.startDate.year}',
                        '${t.origin} -> ${t.destination}',
                        t.vehicleId ?? 'S/P',
                        '${km.toStringAsFixed(0)} KM',
                        isLong ? 'Largo' : 'Local',
                        montoStr
                      ]);
                    }
                    return rows;
                  }(),
                ),
            
            pw.SizedBox(height: 30),
            
            pw.Center(
               child: pw.Text('Documento generado automáticamente por HEIRLOG-TMS (powered by Bitácora)', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))
            )
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    
    await Printing.sharePdf(
        bytes: bytes, 
        filename: 'Rendicion_Viaticos_${user.nombre.replaceAll(' ', '_')}.pdf'
    );
  }

  static pw.Widget _buildKpiCard(String title, String value, {PdfColor color = PdfColors.grey200}) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 4),
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

