import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:bitacora/features/auth/presentation/providers/auth_provider.dart';
import 'package:bitacora/features/admin/presentation/providers/admin_provider.dart';
import 'package:bitacora/features/admin/domain/models/company_config_model.dart';
import 'package:bitacora/features/trips/domain/models/trip_model.dart';
import 'package:bitacora/features/auth/domain/models/user_model.dart';
import 'package:bitacora/features/trips/presentation/providers/trip_provider.dart';
import 'package:bitacora/core/utils/pdf_generator.dart';
import 'package:printing/printing.dart';
class MonthlySummaryScreen extends ConsumerStatefulWidget {
  final String? userId; // Si es null, usa el usuario actual (Conductor)
  
  const MonthlySummaryScreen({super.key, this.userId});

  @override
  ConsumerState<MonthlySummaryScreen> createState() => _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends ConsumerState<MonthlySummaryScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.userId ?? ref.watch(currentUserProfileProvider).value?.uid;
    if (currentUserId == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Necesitamos: Config de Empresa, Datos del Conductor, Viajes del Mes
    final configAsync = ref.watch(companyConfigProvider);
    final driversAsync = ref.watch(choferesProvider);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Resumen del Mes', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _selectMonth(context),
          )
        ],
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
        data: (config) => driversAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
          error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
          data: (drivers) {
            final driver = drivers.firstWhere((d) => d.uid == currentUserId, orElse: () => UserModel(uid: '', nombre: 'Desconocido', email: '', rol: 'CHOFER', idEmpresa: ''));
            
            return FutureBuilder<List<TripModel>>(
              future: ref.read(adminRepositoryProvider).getTripsForMonth(driver.idEmpresa, _selectedMonth),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));
                
                final trips = snapshot.data!.where((t) => t.idChofer == driver.uid).toList();
                
                // Comisión:
                double totalFacturacion = 0;
                for(var t in trips) {
                  totalFacturacion += t.value;
                }
                final comision = totalFacturacion * ((config?.porcentajeComision ?? 0) / 100);
                
                // Viáticos: Siempre Por Jornada
                double viaticos = 0;
                
                final Map<String, List<TripModel>> tripsByDay = {};
                for (var t in trips) {
                  final dayKey = "${t.startDate.year}-${t.startDate.month}-${t.startDate.day}";
                  tripsByDay.putIfAbsent(dayKey, () => []).add(t);
                }

                tripsByDay.forEach((day, dayTrips) {
                  bool hasLongTrip = dayTrips.any((t) => (t.totalKm ?? 0) >= (config?.umbralKilometrosViatico ?? 100));
                  viaticos += hasLongTrip ? (driver.montoViaticoLargo ?? 10000) : (driver.montoViaticoLocal ?? 6500);
                });

                // Helper para saber qué viaje "paga" el viático en modo jornada
                final List<String> primaryTripIds = [];
                final Map<String, String> dayToPrimaryId = {};
                // Ordenamos para que el viaje "Largo" sea el primario si existe
                final sortedTrips = List<TripModel>.from(trips)..sort((a, b) => (b.totalKm ?? 0).compareTo(a.totalKm ?? 0));
                for (var t in sortedTrips) {
                  final dayKey = "${t.startDate.year}-${t.startDate.month}-${t.startDate.day}";
                  if (!dayToPrimaryId.containsKey(dayKey)) {
                    dayToPrimaryId[dayKey] = t.id;
                  }
                }
                primaryTripIds.addAll(dayToPrimaryId.values);

                // Nuevas métricas
                int totalKm = 0;
                final Map<String, double> facturacionPorCliente = {};
                for (var t in trips) {
                   totalKm += (t.totalKm ?? 0).toInt();
                   if (t.client.isNotEmpty) {
                      facturacionPorCliente[t.client] = (facturacionPorCliente[t.client] ?? 0) + t.value;
                   }
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMonthHeader(),
                      const SizedBox(height: 24),
                      
                      // Tarjetas de Resumen
                      Row(
                        children: [
                          Expanded(child: _summaryCard('Viajes', '${trips.length}', Icons.local_shipping, Colors.blueAccent)),
                          const SizedBox(width: 12),
                          Expanded(child: _summaryCard('Total KM', '$totalKm', Icons.route, Colors.purpleAccent)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _summaryCard('Viáticos', _fmt(viaticos), Icons.payments_outlined, Colors.greenAccent)),
                          const SizedBox(width: 12),
                          Expanded(child: _summaryCard('Comisión (${config?.porcentajeComision ?? 0}%)', _fmt(comision), Icons.trending_up, Colors.orangeAccent)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _summaryCard('Facturación Camión', _fmt(totalFacturacion), Icons.monetization_on, Colors.yellow),
                      
                      if (facturacionPorCliente.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text('Desglose por Cliente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 12),
                        ...facturacionPorCliente.entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key, style: const TextStyle(color: Colors.white70)),
                              Text(_fmt(e.value), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )),
                      ],
                      
                      const SizedBox(height: 32),
                      const Text('Detalle de Viajes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 16),
                      
                      ...trips.map((t) {
                        final isPrimary = primaryTripIds.contains(t.id);
                        return _tripItem(t, config!, driver, isPrimary: isPrimary);
                      }),
                      
                      const SizedBox(height: 40),
                      
                      // Botones de Acción
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 55,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => _shareViaWhatsApp(driver, trips, viaticos, comision, totalFacturacion, config!),
                                icon: const Icon(Icons.share),
                                label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 55,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE0E0E0),
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => _generateAndSharePdf(
                                  driver: driver,
                                  trips: trips,
                                  viaticos: viaticos,
                                  comision: comision,
                                  totalFacturacion: totalFacturacion,
                                  totalKm: totalKm,
                                  facturacionPorCliente: facturacionPorCliente,
                                ),
                                icon: const Icon(Icons.picture_as_pdf),
                                label: const Text('Generar PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                );
              }
            );
          },
        ),
      ),
    );
  }

  Widget _buildMonthHeader() {
    final months = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${months[_selectedMonth.month]} ${_selectedMonth.year}', 
               style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _tripItem(TripModel t, CompanyConfigModel config, UserModel driver, {bool isPrimary = true}) {
    final km = t.totalKm ?? 0;
    final isLong = km >= config.umbralKilometrosViatico;
    final viatico = isLong ? (driver.montoViaticoLargo ?? 10000) : (driver.montoViaticoLocal ?? 6500);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showEditTripDriverDialog(context, t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isPrimary ? Colors.white10 : Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${t.startDate.day}/${t.startDate.month}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    if (t.guideNumber != null && t.guideNumber!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text('Guía: ${t.guideNumber}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(t.destination, style: TextStyle(
                  color: isPrimary ? Colors.white : Colors.white38, 
                  fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal
                )),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${km.toStringAsFixed(1)} KM', style: TextStyle(color: isLong ? Colors.orangeAccent : Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit, size: 12, color: Colors.white38),
                  ],
                ),
                const SizedBox(height: 4),
                if (isPrimary)
                  Text(_fmt(viatico.toDouble()), style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold))
                else
                  const Text('Incluido en jornada', style: TextStyle(color: Colors.grey, fontSize: 10, fontStyle: FontStyle.italic)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditTripDriverDialog(BuildContext context, TripModel trip) async {
    final guideCtrl = TextEditingController(text: trip.guideNumber ?? '');
    final kmCtrl = TextEditingController(
      text: (trip.totalKm != null && trip.totalKm! > 0) ? trip.totalKm!.toStringAsFixed(1) : '',
    );
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Editar Kilometraje / Guía', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${trip.origin} → ${trip.destination}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              TextFormField(
                controller: guideCtrl,
                keyboardType: TextInputType.text,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nº Guía de Despacho',
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: kmCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Kilómetros aprox. recorridos',
                  suffixText: 'KM',
                  suffixStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa los kilómetros aproximados';
                  }
                  final parsed = double.tryParse(val.replaceAll(',', '.').trim());
                  if (parsed == null || parsed < 0) {
                    return 'Ingresa un valor numérico válido';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFFFFF), foregroundColor: Colors.black),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final parsedKm = double.tryParse(kmCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;

              await ref.read(tripRepositoryProvider).updateTripDetails(
                trip.id,
                guideNumber: guideCtrl.text.trim(),
                totalKm: parsedKm,
              );

              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {}); // Refresca el resumen mensual

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✓ Kilometraje actualizado a ${parsedKm.toStringAsFixed(1)} KM'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _fmt(double n) => NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0).format(n);

  Future<void> _selectMonth(BuildContext context) async {
    // Selector simple de mes/año (puedes mejorar esto con un picker especializado)
    final now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2024),
      lastDate: now,
      helpText: 'Selecciona el mes',
    );
    if (picked != null) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month, 1));
    }
  }

  Future<void> _shareViaWhatsApp(UserModel driver, List<TripModel> trips, double viaticos, double comision, double facturacion, CompanyConfigModel config) async {
    final months = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    final monthStr = '${months[_selectedMonth.month]} ${_selectedMonth.year}';
    
    String message = '*RESUMEN MENSUAL - HEIRLOG-TMS*\n';
    message += '----------------------------------\n';
    message += '*Conductor:* ${driver.nombre}\n';
    message += '*Periodo:* $monthStr\n';
    message += '----------------------------------\n\n';
    message += '*RESUMEN OPERACIONAL:*\n';
    message += '• Viajes Totales: ${trips.length}\n';
    message += '• Facturación Camión: ${_fmt(facturacion)}\n';
    message += '• Viáticos Acumulados: ${_fmt(viaticos)}\n';
    message += '• Comisión (${config.porcentajeComision}%): ${_fmt(comision)}\n';
    message += '----------------------------------\n\n';
    message += '*DETALLE DE VIAJES:*\n';
    
    for (var t in trips) {
      final km = t.totalKm ?? 0;
      message += '• ${t.startDate.day}/${t.startDate.month}: ${t.destination} (${km.toInt()} KM) - ${t.client}\n';
    }
    
    message += '\n_Generado automáticamente por HEIRLOG-TMS (powered by Bitácora)_';

    final encodedMessage = Uri.encodeComponent(message);
    // Para WhatsApp web/app universal es mejor usar wa.me o api.whatsapp.com
    final url = 'https://api.whatsapp.com/send?text=$encodedMessage';
    
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al abrir WhatsApp: $e')));
      }
    }
  }

  Future<void> _generateAndSharePdf({
    required UserModel driver,
    required List<TripModel> trips,
    required double viaticos,
    required double comision,
    required double totalFacturacion,
    required int totalKm,
    required Map<String, double> facturacionPorCliente,
  }) async {
    try {
      final bytes = await PdfGenerator.generateDriverMonthlyReport(
        driver: driver,
        period: _selectedMonth,
        trips: trips,
        viaticos: viaticos,
        comision: comision,
        totalFacturacion: totalFacturacion,
        totalKm: totalKm,
        facturacionPorCliente: facturacionPorCliente,
      );

      final monthStr = '${_selectedMonth.month}_${_selectedMonth.year}';
      final filename = 'Reporte_${driver.nombre.replaceAll(' ', '_')}_$monthStr.pdf';

      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generando PDF: $e')));
      }
    }
  }
}
