import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../../features/auth/domain/models/user_model.dart';

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
                      pw.Text('BITÁCORA TMS', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
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
}
