import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../../features/auth/domain/models/user_model.dart';
import '../../features/trips/domain/models/trip_model.dart';

class PdfGenerator {
  static Future<Uint8List> generateLiquidacionSueldo({
    required UserModel driver,
    required Map<String, dynamic> payslipData,
    required DateTime period,
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);

    // Extract Data
    final sueldoBase = payslipData['Sueldo Base'] ?? 0.0;
    final comisiones = payslipData['Comisiones'] ?? 0.0;
    final gratificacion = payslipData['Gratificación Legal'] ?? 0.0;
    final totalImponible = payslipData['Total Imponible'] ?? 0.0;
    final viaticos = payslipData['Viáticos (No Imponible)'] ?? 0.0;
    final totalHaberes = payslipData['Total Haberes'] ?? 0.0;

    final afp = payslipData['AFP'] ?? 0.0;
    final salud = payslipData['Salud'] ?? 0.0;
    final cesantia = payslipData['Seguro Cesantía (Trabajador)'] ?? 0.0;
    final totalDescuentos = payslipData['Total Descuentos'] ?? 0.0;
    
    final liquido = payslipData['Sueldo Líquido'] ?? 0.0;

    final monthStr = DateFormat('MMMM yyyy', 'es_CL').format(period).toUpperCase();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // HEADER
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('HEIRLOG-TMS', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Liquidación de Remuneraciones', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text('Período: $monthStr', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
              pw.SizedBox(height: 30),

              // EMPLOYEE INFO
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
                          pw.Text('Trabajador: ${driver.nombre}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text('RUT: ${driver.rut ?? 'Sin RUT'}'),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Cargo: Conductor Profesional'),
                          pw.SizedBox(height: 4),
                          pw.Text('Contrato: ${driver.tipoContrato ?? 'Indefinido'}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // DETAILS TABLE
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // HABERES
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          color: PdfColors.grey300,
                          child: pw.Text('HABERES', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.SizedBox(height: 8),
                        _buildRow('Sueldo Base', sueldoBase, currency),
                        _buildRow('Comisiones', comisiones, currency),
                        _buildRow('Gratificación Legal', gratificacion, currency),
                        pw.Divider(color: PdfColors.grey400),
                        _buildRow('Total Imponible', totalImponible, currency, isBold: true),
                        pw.SizedBox(height: 12),
                        _buildRow('Viáticos (No Imponible)', viaticos, currency),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  
                  // DESCUENTOS
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          color: PdfColors.grey300,
                          child: pw.Text('DESCUENTOS LEGALES', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.SizedBox(height: 8),
                        _buildRow('AFP', afp, currency),
                        _buildRow('Salud', salud, currency),
                        _buildRow('Seguro de Cesantía (0.6%)', cesantia, currency),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.black, thickness: 1.5),
              pw.SizedBox(height: 8),

              // TOTALS
              pw.Row(
                children: [
                  pw.Expanded(child: _buildRow('TOTAL HABERES', totalHaberes, currency, isBold: true)),
                  pw.SizedBox(width: 20),
                  pw.Expanded(child: _buildRow('TOTAL DESCUENTOS', totalDescuentos, currency, isBold: true)),
                ],
              ),
              
              pw.SizedBox(height: 30),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    border: pw.Border.all(color: PdfColors.black),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text('LÍQUIDO A PAGO: ', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(width: 16),
                      pw.Text(currency.format(liquido), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ),

              pw.Spacer(),

              // SIGNATURES
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 150, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 8),
                      pw.Text('Firma Empleador', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 150, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 8),
                      pw.Text('Firma Trabajador', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Recibí conforme', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildRow(String label, double amount, NumberFormat currency, {bool isBold = false}) {
    if (amount == 0 && !isBold) return pw.SizedBox(); // Hide zero values for cleaner look
    
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(currency.format(amount), style: pw.TextStyle(fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  static Future<Uint8List> generateDriverMonthlyReport({
    required UserModel driver,
    required DateTime period,
    required List<TripModel> trips,
    required double viaticos,
    required double comision,
    required double totalFacturacion,
    required int totalKm,
    required Map<String, double> facturacionPorCliente,
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);
    final monthStr = DateFormat('MMMM yyyy', 'es_CL').format(period).toUpperCase();

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
                    pw.Text('Reporte Mensual de Operaciones', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text('Período: $monthStr', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
                        pw.Text('Conductor: ${driver.nombre}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text('RUT: ${driver.rut ?? 'Sin RUT'}'),
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
                _buildKpiCard('Total KM', '$totalKm km'),
                _buildKpiCard('Facturación Camión', currency.format(totalFacturacion)),
              ],
            ),
            pw.SizedBox(height: 20),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildKpiCard('Comisión', currency.format(comision), color: PdfColors.orange100),
                _buildKpiCard('Viáticos', currency.format(viaticos), color: PdfColors.green100),
              ],
            ),
            pw.SizedBox(height: 30),

            // DESGLOSE POR CLIENTE
            if (facturacionPorCliente.isNotEmpty) ...[
              pw.Text('Desglose por Cliente', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                context: context,
                headers: ['Cliente', 'Monto Facturado'],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                data: facturacionPorCliente.entries.map((e) => [e.key, currency.format(e.value)]).toList(),
              ),
              pw.SizedBox(height: 30),
            ],

            // DETALLE DE VIAJES
            pw.Text('Detalle de Viajes', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: ['Fecha', 'Guía', 'Destino', 'Contenedor', 'KM', 'Cliente', 'Tipo', 'Valor'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 10),
              data: trips.map((t) {
                return [
                  '${t.startDate.day}/${t.startDate.month}/${t.startDate.year}',
                  t.guideNumber ?? '-',
                  t.destination,
                  t.containerNumber ?? '-',
                  '${t.totalKm?.toInt() ?? 0}',
                  t.client,
                  t.billingType,
                  currency.format(t.value),
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 30),
            
            pw.Center(
               child: pw.Text('Documento generado automáticamente por HEIRLOG-TMS (powered by Bitácora)', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))
            )
          ];
        },
      ),
    );

    return pdf.save();
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
