import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bitacora/features/auth/presentation/providers/auth_provider.dart';
import 'package:bitacora/features/admin/presentation/widgets/kpi_dashboard_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/viaticos_admin_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/flota_admin_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/ziyu_conciliation_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/liquidaciones_admin_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/remuneraciones_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/analytics_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/conductores_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/config_admin_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/control_tower_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/service_requests_inbox_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/mantenimiento_admin_view.dart';
import 'package:bitacora/features/admin/presentation/widgets/fuel_performance_view.dart';
import 'package:bitacora/features/admin/presentation/screens/cotizador_screen.dart';
import 'package:bitacora/features/admin/presentation/providers/admin_provider.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProfileProvider).value;

    if (user != null && user.rol == 'SUPERADMIN') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/superadmin');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Badge de pendientes para el ítem de viáticos
    final viaticosAsync = ref.watch(adminViaticosProvider);
    final pendientesCount = viaticosAsync.value?.where((v) => v.isPendiente).length ?? 0;
    // Alertas de documentos de flota próximos a vencer (30 días)
    final vehiclesAsync = ref.watch(adminVehiclesProvider);
    final vehicles = vehiclesAsync.value ?? [];
    final expiringAlerts = vehicles
        .expand((v) => v.getExpiringDocuments(30).map((d) => (vehicle: v, doc: d)))
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;

        return Scaffold(
          appBar: isMobile
              ? AppBar(
                  title: const Text('Panel de Administración'),
                  backgroundColor: const Color(0xFF161616),
                  elevation: 0,
                )
              : null,
          drawer: isMobile ? Drawer(child: _buildSidebar(pendientesCount, isDrawer: true)) : null,
          body: Row(
            children: [
              if (!isMobile) _buildSidebar(pendientesCount),
              Expanded(
                child: Column(
                  children: [
                    if (expiringAlerts.isNotEmpty)
                      _FleetDocumentAlertBanner(alerts: expiringAlerts),
                    Expanded(child: _buildMainContent()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar(int pendientesCount, {bool isDrawer = false}) {
    final items = [
      (Icons.dashboard_outlined, 'Dashboard', 0),
      (Icons.satellite_alt_outlined, 'Torre de Control', 0),
      (Icons.auto_awesome_outlined, 'Solicitudes IA', 0),
      (Icons.analytics_outlined, 'Analítica', 0),
      (Icons.local_gas_station, 'Rendimiento & Diésel', 0),
      (Icons.cloud_sync_outlined, 'Ziyu / Proformas', 0),
      (Icons.calculate_outlined, 'Cotizador', 0),
      (Icons.receipt_outlined, 'Liquidaciones', 0),
      (Icons.payments_outlined, 'Remuneraciones', 0),
      (Icons.receipt_long_outlined, 'Viáticos', pendientesCount),
      (Icons.local_shipping_outlined, 'Flota', 0),
      (Icons.build_circle_outlined, 'Mantenimiento', 0),
      (Icons.group_outlined, 'Conductores', 0),
      (Icons.settings_outlined, 'Configuración', 0),
    ];

    return Container(
      width: isDrawer ? null : 240,
      color: const Color(0xFF161616),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDrawer)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Text('MENÚ PRINCIPAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
            child: Text('NAVEGACIÓN',
                style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = _selectedIndex == index;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    selected: isSelected,
                    selectedTileColor: const Color(0xFF262626),
                    leading: Icon(
                      item.$1,
                      size: 20,
                      color: isSelected ? Colors.white : Colors.grey,
                    ),
                    title: Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? Colors.white : Colors.grey,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: item.$3 > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${item.$3}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          )
                        : null,
                    onTap: () {
                      setState(() => _selectedIndex = index);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const Icon(Icons.logout, size: 20, color: Colors.redAccent),
              title: const Text('Cerrar Sesión',
                  style: TextStyle(fontSize: 13, color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onTap: () async {
                await ref.read(authServiceProvider).signOut();
                if (mounted) context.go('/login');
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Text(
              'HEIRLOG-TMS v1.0\npowered by Bitácora TMS',
              style: TextStyle(color: Colors.white24, fontSize: 10, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return IndexedStack(
      index: _selectedIndex.clamp(0, 13),
      children: const [
        KpiDashboardView(),
        ControlTowerView(),
        ServiceRequestsInboxView(),
        AnalyticsView(),
        FuelPerformanceView(),
        ZiyuConciliationView(),
        CotizadorScreen(),
        LiquidacionesAdminView(),
        RemuneracionesView(),
        ViaticosAdminView(),
        FlotaAdminView(),
        MantenimientoAdminView(),
        ConductoresView(),
        ConfigAdminView(),
      ],
    );
  }
}

// ─── Banner de alertas de documentos de flota ─────────────────────────────────

class _FleetDocumentAlertBanner extends StatelessWidget {
  final List<({dynamic vehicle, Map<String, dynamic> doc})> alerts;
  const _FleetDocumentAlertBanner({required this.alerts});

  @override
  Widget build(BuildContext context) {
    // Si hay alguno crítico (<= 1 día), banner rojo; si no, naranja
    final hasCritical = alerts.any((a) => a.doc['esCritico'] == true);
    final bgColor = hasCritical ? const Color(0xFF3B1010) : const Color(0xFF332005);
    final borderColor = hasCritical ? Colors.redAccent.shade700 : Colors.amber.shade700;
    final iconColor = hasCritical ? Colors.redAccent : Colors.amberAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor, width: 1.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    children: [
                      TextSpan(
                        text: '⚠ DOCUMENTOS DE FLOTA: ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: iconColor,
                        ),
                      ),
                      TextSpan(
                        text: '${alerts.length} documento(s) por vencer en los próximos 30 días.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  alerts.take(3).map((a) {
                    final dias = a.doc['diasRestantes'] as int;
                    final plazo = dias < 0
                        ? '¡VENCIDO hace ${-dias}d!'
                        : dias == 0
                            ? '¡Vence HOY!'
                            : 'vence en ${dias}d';
                    return '${a.vehicle.patente}: ${a.doc['nombre']} ($plazo)';
                  }).join('  ·  ') + (alerts.length > 3 ? '  ·  ...' : ''),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
