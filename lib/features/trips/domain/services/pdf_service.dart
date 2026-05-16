import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
    
    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) {
          return [
            pw.Text('Rendicion de Viaticos', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            pw.Text('Conductor: ${user.nombre}', style: const pw.TextStyle(fontSize: 16)),
            pw.Text('Empresa ID: ${user.idEmpresa}', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
            pw.Text('Periodo: ${start.day}/${start.month}/${start.year} al ${end.day}/${end.month}/${end.year}', style: const pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 24),
            pw.Text('Detalle de Viajes Realizados:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            if (trips.isEmpty)
               pw.Text('No hay viajes registrados en este periodo.', style: const pw.TextStyle(fontSize: 14))
            else
                pw.TableHelper.fromTextArray(
                  headers: ['Fecha', 'Ruta', 'KM', 'Tipo', 'Monto'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellAlignment: pw.Alignment.centerLeft,
                  data: () {
                    final List<List<String>> rows = [];
                    final Map<String, bool> dayHasPaid = {};
                    for (var t in trips) {
                      final km = t.totalKm ?? 0.0;
                      final isLong = km >= config.umbralKilometrosViatico;
                      final dayKey = '${t.startDate.year}-${t.startDate.month}-${t.startDate.day}';
                      String montoStr = '';
                      if (config.tipoViatico == 'POR_JORNADA') {
                        if (dayHasPaid.containsKey(dayKey)) {
                          montoStr = 'Incluido';
                        } else {
                          final dayTrips = trips.where((tri) => 
                            '${tri.startDate.year}-${tri.startDate.month}-${tri.startDate.day}' == dayKey).toList();
                          final hasLong = dayTrips.any((tri) => (tri.totalKm ?? 0) >= config.umbralKilometrosViatico);
                          final monto = hasLong ? (user.montoViaticoLargo ?? 10000) : (user.montoViaticoLocal ?? 6500);
                          montoStr = '\$ ${monto.toInt()}';
                          dayHasPaid[dayKey] = true;
                        }
                      } else {
                        final monto = isLong ? (user.montoViaticoLargo ?? 10000) : (user.montoViaticoLocal ?? 6500);
                        montoStr = '\$ ${monto.toInt()}';
                      }
                      rows.add([
                        '${t.startDate.day}/${t.startDate.month}/${t.startDate.year}',
                        '${t.origin} -> ${t.destination}',
                        '${km.toStringAsFixed(0)} KM',
                        isLong ? 'Largo' : 'Local',
                        montoStr
                      ]);
                    }
                    return rows;
                  }(),
                ),
            pw.SizedBox(height: 32),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Viajes Computados: ${trips.length}', style: const pw.TextStyle(fontSize: 14)),
                pw.Text('TOTAL A PAGAR: \$ ${_calculateTotal(trips, user, config)}', 
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              ],
            ),
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

  static String _calculateTotal(List<TripModel> trips, UserModel user, CompanyConfigModel config) {
    if (config.tipoViatico == 'POR_VIAJE') {
      double total = 0;
      for (final t in trips) {
        final km = t.totalKm ?? 0.0;
        final isLong = km >= config.umbralKilometrosViatico;
        total += isLong ? (user.montoViaticoLargo ?? 10000) : (user.montoViaticoLocal ?? 6500);
      }
      return total.toInt().toString();
    } else {
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
      return total.toInt().toString();
    }
  }
}
