import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import 'package:flutter/foundation.dart';

import '../models/cotizacion_model.dart';
import '../models/company_config_model.dart';

class CotizacionPdfService {
  static Future<Uint8List> generarProformaPdf({
    required CotizacionModel cotizacion,
    required CompanyConfigModel config,
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat.currency(locale: 'es_CL', symbol: '\$', customPattern: '\$#,##0', decimalDigits: 0);

    // Intentar cargar logo
    pw.MemoryImage? logoImage;
    try {
      if (config.emisorLogoBase64.isNotEmpty) {
        String base64String = config.emisorLogoBase64;
        if (base64String.contains(',')) {
          base64String = base64String.split(',').last;
        }
        
        // Limpiar cualquier espacio o salto de línea que rompa la decodificación
        base64String = base64String.replaceAll(RegExp(r'\s+'), '');
        final decodedBytes = base64Decode(base64String);
        
        if (decodedBytes.isNotEmpty) {
          logoImage = pw.MemoryImage(decodedBytes);
        }
      }
    } catch (e) {
      debugPrint('Error decodificando logo en PDF: $e');
    }

    final dateStr = DateFormat('dd/MM/yyyy').format(cotizacion.createdAt);
    
    // Cálculos
    final tarifaNeta = cotizacion.tarifaPropuesta;
    final iva = tarifaNeta * 0.19;
    final total = tarifaNeta + iva;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. ENCABEZADO / MEMBRETE
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      width: 120,
                      height: 60,
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    )
                  else
                    pw.SizedBox(width: 120, height: 60),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (config.emisorRazonSocial.isNotEmpty) pw.Text(config.emisorRazonSocial, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        if (config.emisorRut.isNotEmpty) pw.Text('RUT: ${config.emisorRut}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        if (config.emisorGiro.isNotEmpty) pw.Text('Giro: ${config.emisorGiro}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        if (config.emisorDireccion.isNotEmpty) pw.Text(config.emisorDireccion, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        if (config.emisorTelefono.isNotEmpty) pw.Text('Tel: ${config.emisorTelefono}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        if (config.emisorEmail.isNotEmpty) pw.Text(config.emisorEmail, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ],
              ),
              
              pw.SizedBox(height: 40),
              
              pw.Center(
                child: pw.Text('COTIZACIÓN DE SERVICIO DE TRANSPORTE', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
              ),
              pw.SizedBox(height: 10),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text('N° Cotización: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  pw.Text(cotizacion.numeroCotizacion.isNotEmpty ? cotizacion.numeroCotizacion : 'S/N', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(width: 20),
                  pw.Text('Fecha: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  pw.Text(dateStr, style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.SizedBox(height: 30),

              // 2. DATOS DEL CLIENTE (solo si hay datos)
              if (cotizacion.clienteNombre.isNotEmpty || cotizacion.clienteRut.isNotEmpty || cotizacion.clienteContacto.isNotEmpty) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('DATOS DEL CLIENTE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.orange800)),
                      pw.SizedBox(height: 8),
                      if (cotizacion.clienteNombre.isNotEmpty) 
                        pw.Row(children: [pw.Text('Señor(es): ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)), pw.Text(cotizacion.clienteNombre, style: const pw.TextStyle(fontSize: 10))]),
                      if (cotizacion.clienteRut.isNotEmpty) 
                        pw.Row(children: [pw.Text('RUT: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)), pw.Text(cotizacion.clienteRut, style: const pw.TextStyle(fontSize: 10))]),
                      if (cotizacion.clienteContacto.isNotEmpty) 
                        pw.Row(children: [pw.Text('Contacto: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)), pw.Text(cotizacion.clienteContacto, style: const pw.TextStyle(fontSize: 10))]),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),
              ],

              // 3. DETALLE DEL SERVICIO
              pw.Text('DETALLE DEL SERVICIO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.orange800)),
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
                child: pw.Text('Ruta: ${cotizacion.origen} a ${cotizacion.destino}${cotizacion.idaYVuelta ? ' (Ida y vuelta)' : ''}', style: const pw.TextStyle(fontSize: 12)),
              ),
              pw.SizedBox(height: 30),

              // 4. TABLA DE VALORES
              pw.Container(
                width: double.infinity,
                child: pw.Table(
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1),
                  },
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Concepto', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Monto', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.right)),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Servicio de transporte (neto)', style: const pw.TextStyle(fontSize: 10))),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(currency.format(tarifaNeta), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('IVA (19%)', style: const pw.TextStyle(fontSize: 10))),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(currency.format(iva), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
                      ],
                    ),
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.orange50),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.orange800))),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(currency.format(total), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.orange800), textAlign: pw.TextAlign.right)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // 5. TÉRMINOS Y CONDICIONES
              pw.Text('TÉRMINOS Y CONDICIONES', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(
                'Las eventuales sobreestadías no contempladas en esta cotización se facturarán de forma adicional. Para confirmar el servicio, favor responder con orden de compra o aceptación formal. Cotización válida por 15 días desde la fecha de emisión.',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                textAlign: pw.TextAlign.justify,
              ),

              pw.SizedBox(height: 20),

              // 6. PIE
              pw.Divider(color: PdfColors.grey400, thickness: 1),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(config.emisorRazonSocial.isNotEmpty ? config.emisorRazonSocial : 'HEIRLOG-TMS', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
