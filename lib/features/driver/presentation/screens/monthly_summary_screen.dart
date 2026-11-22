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
import 'package:bitacora/core/theme/app_theme.dart';
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Resumen del Mes', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3, color: AppColors.textPrimary)),
        backgroundColor: AppColors.background.withValues(alpha: 0.85),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _selectMonth(context),
          )
        ],
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
        data: (config) => driversAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
          data: (drivers) {
            final driver = drivers.firstWhere((d) => d.uid == currentUserId, orElse: () => UserModel(uid: '', nombre: 'Desconocido', email: '', rol: 'CHOFER', idEmpresa: ''));
            
            return FutureBuilder<List<TripModel>>(
              future: ref.read(adminRepositoryProvider).getTripsForMonth(driver.idEmpresa, _selectedMonth),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                
                final trips = snapshot.data!.where((t) => t.idChofer == driver.uid).toList();
                
                // Comisión: solo viajes operativos
                double totalFacturacion = 0;
                for(var t in trips) {
                  if (t.isOperativo) {
                    totalFacturacion += t.value;
                  }
                }
                final comision = totalFacturacion * ((config?.porcentajeComision ?? 0) / 100);
                
                // Viáticos: Solo se generan por viajes operativos
                double viaticos = 0;
                
                final Map<String, List<TripModel>> tripsByDay = {};
                for (var t in trips) {
                  if (t.isOperativo) {
                    final dayKey = "${t.startDate.year}-${t.startDate.month}-${t.startDate.day}";
                    tripsByDay.putIfAbsent(dayKey, () => []).add(t);
                  }
                }

                tripsByDay.forEach((day, dayTrips) {
                  bool hasLongTrip = dayTrips.any((t) => (t.totalKm ?? 0) >= (config?.umbralKilometrosViatico ?? 100));
                  viaticos += hasLongTrip ? (driver.montoViaticoLargo ?? 10000) : (driver.montoViaticoLocal ?? 6500);
                });

                // Helper para saber qué viaje "paga" el viático en modo jornada
                final List<String> primaryTripIds = [];
                final Map<String, String> dayToPrimaryId = {};
                // Ordenamos para que el viaje "Largo" sea el primario si existe (solo operativos)
                final sortedTrips = List<TripModel>.from(trips.where((t) => t.isOperativo))..sort((a, b) => (b.totalKm ?? 0).compareTo(a.totalKm ?? 0));
                for (var t in sortedTrips) {
                  final dayKey = "${t.startDate.year}-${t.startDate.month}-${t.startDate.day}";
                  if (!dayToPrimaryId.containsKey(dayKey)) {
                    dayToPrimaryId[dayKey] = t.id;
                  }
                }
                primaryTripIds.addAll(dayToPrimaryId.values);

                // Nuevas métricas: todos los movimientos suman KM al odómetro
                int totalKm = 0;
                final Map<String, double> facturacionPorCliente = {};
                for (var t in trips) {
                   totalKm += (t.totalKm ?? 0).toInt();
                   if (t.isOperativo && t.client.isNotEmpty) {
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
        color: const Color(0xFF161A22),
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
        color: const Color(0xFF161A22),
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
    final isNoRevenue = !t.isOperativo;
    final hasFreight = t.isOperativo && t.value > 0;
    final dateFormatted = DateFormat('EEE dd/MM', 'es_CL').format(t.startDate);

    // Resolución limpia de Patente: si vehicleId es un ID de Firestore (ej: VEH-178...), busca la patente real en vehiclesProvider
    final vehicles = ref.watch(vehiclesProvider).value ?? [];
    String displayPlate = '';
    if (t.vehicleId != null && t.vehicleId!.isNotEmpty) {
      final rawVid = t.vehicleId!.trim();
      final match = vehicles.where((v) => v.id == rawVid || v.patente.toUpperCase() == rawVid.toUpperCase()).firstOrNull;
      displayPlate = match != null ? match.patente : (rawVid.startsWith('VEH-') ? (driver.patenteAsignada ?? rawVid) : rawVid);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161A22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: t.isRetiroAnticipado
              ? Colors.amber.withValues(alpha: 0.35)
              : (t.isMantenimiento
                  ? Colors.cyan.withValues(alpha: 0.35)
                  : (isPrimary ? Colors.white24 : Colors.white10)),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showTripDetailSheet(context, t, config, driver, isPrimary: isPrimary),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. HEADER ROW: FECHA + BADGE TIPO + VIÁTICO
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_outlined, size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          dateFormatted.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  if (t.isRetiroAnticipado)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 0.8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 11, color: Colors.amberAccent),
                          SizedBox(width: 4),
                          Text('RETIRO VACÍO', style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  else if (t.isMantenimiento)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.cyan.withValues(alpha: 0.5), width: 0.8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.build_circle_outlined, size: 11, color: Colors.cyanAccent),
                          SizedBox(width: 4),
                          Text('MANTENCIÓN', style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.35), width: 0.8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_shipping_outlined, size: 11, color: Colors.greenAccent),
                          SizedBox(width: 4),
                          Text('OPERATIVO', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),

                  const Spacer(),

                  if (isNoRevenue)
                    const Text('Sin Viático (\$0)', style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic))
                  else if (isPrimary)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Viático: ${_fmt(viatico.toDouble())}',
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    )
                  else
                    const Text('En Jornada', style: TextStyle(color: Colors.white54, fontSize: 11, fontStyle: FontStyle.italic)),
                ],
              ),

              const SizedBox(height: 10),

              // 2. CLIENTE (SI APLICA)
              if (t.client.isNotEmpty && t.client.toUpperCase() != 'RETIRO ANTICIPADO' && t.client.toUpperCase() != 'MANTENIMIENTO') ...[
                Row(
                  children: [
                    const Icon(Icons.business_rounded, color: Colors.amber, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t.client.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // 3. RUTA VISUAL CLARA
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🟢 ', style: TextStyle(fontSize: 10)),
                        Expanded(
                          child: Text(
                            t.origin.trim().isNotEmpty ? t.origin.trim() : 'ORIGEN',
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    if (t.paradasIntermedias != null && t.paradasIntermedias!.isNotEmpty)
                      for (final p in t.paradasIntermedias!)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(' ↳ 🏢 ', style: TextStyle(fontSize: 10)),
                              Expanded(
                                child: Text(
                                  p.trim(),
                                  style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🏁 ', style: TextStyle(fontSize: 10)),
                          Expanded(
                            child: Text(
                              (t.puntoDescarga != null && t.puntoDescarga!.trim().isNotEmpty)
                                  ? t.puntoDescarga!.trim()
                                  : (t.destination.trim().isNotEmpty ? t.destination.trim() : 'DESTINO'),
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // 4. IDENTIFICADORES Y CHIPS
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (t.guideNumber != null && t.guideNumber!.isNotEmpty)
                    _buildChip(Icons.description_outlined, 'Guía: ${t.guideNumber}', Colors.white70),
                  if (t.containerNumber != null && t.containerNumber!.isNotEmpty)
                    _buildChip(Icons.crop_square_rounded, 'Cont: ${t.containerNumber}', Colors.cyanAccent),
                  if (t.bookingNumber != null && t.bookingNumber!.isNotEmpty)
                    _buildChip(Icons.bookmark_outline_rounded, 'Bkg: ${t.bookingNumber}', Colors.purpleAccent),
                  if (displayPlate.isNotEmpty)
                    _buildChip(Icons.local_shipping_outlined, displayPlate, Colors.orangeAccent),
                ],
              ),

              const SizedBox(height: 10),

              // 5. FOOTER: KILOMETRAJE + FLETE + BOTONES
              Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isLong ? Colors.orange : Colors.blue).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (isLong ? Colors.orangeAccent : Colors.blueAccent).withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.route, size: 12, color: isLong ? Colors.orangeAccent : Colors.blueAccent),
                        const SizedBox(width: 4),
                        Text(
                          '${km.toStringAsFixed(1)} KM',
                          style: TextStyle(
                            color: isLong ? Colors.orangeAccent : Colors.blueAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  if (hasFreight)
                    Text(
                      'Flete: ${_fmt(t.value)}',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),

                  const Spacer(),

                  InkWell(
                    onTap: () => _showEditTripDriverDialog(context, t),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined, size: 14, color: Colors.white70),
                          SizedBox(width: 4),
                          Text('Editar', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_ios, size: 11, color: Colors.white38),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showTripDetailSheet(BuildContext context, TripModel t, CompanyConfigModel config, UserModel driver, {bool isPrimary = true}) {
    final km = t.totalKm ?? 0;
    final isLong = km >= config.umbralKilometrosViatico;
    final viatico = isLong ? (driver.montoViaticoLargo ?? 10000) : (driver.montoViaticoLocal ?? 6500);
    final isNoRevenue = !t.isOperativo;
    final dateStr = DateFormat('EEEE dd \'de\' MMMM, yyyy', 'es_CL').format(t.startDate);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF161A22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white24, width: 1)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ficha Detallada del Viaje', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Text(dateStr[0].toUpperCase() + dateStr.substring(1), style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 16),

              _detailRow('Cliente / Mandante', t.client.isNotEmpty ? t.client : 'Sin cliente asignado', Icons.business_rounded, Colors.amber),
              _detailRow('Tipo Movimiento', t.isRetiroAnticipado ? 'Retiro Anticipado (Vacío)' : (t.isMantenimiento ? 'Mantenimiento / Taller' : 'Operativo (Flete Comercial)'), Icons.local_shipping_outlined, Colors.greenAccent),
              if (t.status.isNotEmpty)
                _detailRow('Estado Operativo', t.status, Icons.verified_outlined, Colors.blueAccent),

              const Divider(color: Colors.white12, height: 24),

              _detailRow('Nº Guía de Despacho', (t.guideNumber != null && t.guideNumber!.isNotEmpty) ? t.guideNumber! : 'Pendiente / No registrada', Icons.description_outlined, Colors.white70),
              if (t.containerNumber != null && t.containerNumber!.isNotEmpty)
                _detailRow('Contenedor (ISO 6346)', t.containerNumber!, Icons.crop_square_rounded, Colors.cyanAccent),
              if (t.bookingNumber != null && t.bookingNumber!.isNotEmpty)
                _detailRow('Booking', t.bookingNumber!, Icons.bookmark_border_rounded, Colors.purpleAccent),
              if (t.vehicleId != null && t.vehicleId!.isNotEmpty) ...[
                Builder(builder: (context) {
                  final vehicles = ref.read(vehiclesProvider).value ?? [];
                  final rawVid = t.vehicleId!.trim();
                  final match = vehicles.where((v) => v.id == rawVid || v.patente.toUpperCase() == rawVid.toUpperCase()).firstOrNull;
                  final plate = match != null ? '${match.patente} (${match.marca} ${match.modelo})' : (driver.patenteAsignada ?? rawVid);
                  return _detailRow('Patente Camión', plate, Icons.local_shipping_outlined, Colors.orangeAccent);
                }),
              ],

              const Divider(color: Colors.white12, height: 24),

              const Text('Ruta Registrada', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🟢 Origen: ${t.origin.isNotEmpty ? t.origin : "Base/Casa"}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    if (t.paradasIntermedias != null && t.paradasIntermedias!.isNotEmpty)
                      for (final p in t.paradasIntermedias!)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('  ↳ 🏢 Parada: $p', style: const TextStyle(color: Colors.amberAccent, fontSize: 13)),
                        ),
                    const SizedBox(height: 4),
                    Text('🏁 Destino / Descarga: ${(t.puntoDescarga != null && t.puntoDescarga!.isNotEmpty) ? t.puntoDescarga! : t.destination}', style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),

              const Divider(color: Colors.white12, height: 24),

              Row(
                children: [
                  Expanded(
                    child: _detailMetricCard(
                      'Distancia',
                      '${km.toStringAsFixed(1)} KM',
                      isLong ? 'Ruta Larga (≥ ${config.umbralKilometrosViatico} KM)' : 'Ruta Local',
                      isLong ? Colors.orangeAccent : Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _detailMetricCard(
                      'Viático Conductor',
                      isNoRevenue ? '\$0' : _fmt(viatico.toDouble()),
                      isNoRevenue ? 'Sin viático comercial' : (isPrimary ? 'Asignado a este viaje' : 'Incluido en jornada'),
                      Colors.greenAccent,
                    ),
                  ),
                ],
              ),
              if (t.isOperativo && t.value > 0) ...[
                const SizedBox(height: 12),
                _detailMetricCard(
                  'Valor Facturación Flete',
                  _fmt(t.value),
                  'Tarifa del servicio de transporte',
                  Colors.amberAccent,
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('EDITAR KILOMETRAJE / GUÍA', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showEditTripDriverDialog(context, t);
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, IconData icon, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailMetricCard(String title, String value, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
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
        backgroundColor: const Color(0xFF161A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Editar Kilometraje / Guía', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trip.displayRoute3Steps, style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
