import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/kpi_dashboard_view.dart';
import '../widgets/viaticos_admin_view.dart';
import '../widgets/flota_admin_view.dart';
import '../widgets/ziyu_conciliation_view.dart';
import '../widgets/liquidaciones_admin_view.dart';
import '../widgets/remuneraciones_view.dart';
import '../widgets/analytics_view.dart';
import '../widgets/conductores_view.dart';
import '../widgets/config_admin_view.dart';
import '../widgets/control_tower_view.dart';
import '../widgets/service_requests_inbox_view.dart';
import '../widgets/mantenimiento_admin_view.dart';
import '../screens/cotizador_screen.dart';
import '../../presentation/providers/admin_provider.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(currentUserProfileProvider).value;
    // Badge de pendientes para el ítem de viáticos
    final viaticosAsync = ref.watch(adminViaticosProvider);
    final pendientesCount = viaticosAsync.value?.where((v) => v.isPendiente).length ?? 0;

    final isMobile = MediaQuery.of(context).size.width < 900;
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        leading: isMobile ? Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ) : null,
        title: Row(
          children: [
            if (!isMobile) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.book, color: Color(0xFFFFFFFF), size: 20),
              ),
              const SizedBox(width: 12),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('HEIRLOG-TMS',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Text('powered by Bitácora TMS',
                    style: TextStyle(fontSize: 9, color: Colors.grey, fontStyle: FontStyle.italic)),
                Text(
                  userProfile?.nombre ?? 'Administrador',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ver modo Conductor',
            icon: const Icon(Icons.directions_car_outlined),
            onPressed: () => context.go('/driver'),
          ),
          if (!isMobile)
            IconButton(
              tooltip: 'Cerrar Sesión',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authServiceProvider).signOut();
                if (context.mounted) {
                  context.go('/login');
                }
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: isMobile ? Drawer(
        backgroundColor: const Color(0xFF161616),
        child: _buildSidebar(pendientesCount, isDrawer: true),
      ) : null,
      body: Row(
        children: [
          if (!isMobile) _buildSidebar(pendientesCount),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  Widget _buildSidebar(int pendientesCount, {bool isDrawer = false}) {
    final items = [
      (Icons.dashboard_outlined, 'Dashboard', 0),
      (Icons.satellite_alt_outlined, 'Torre de Control', 0),
      (Icons.auto_awesome_outlined, 'Solicitudes IA', 0),
      (Icons.analytics_outlined, 'Analítica', 0),
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
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.8)),
          ),
          ...items.asMap().entries.map((entry) {
            final idx = entry.key;
            final (icon, label, badge) = entry.value;
            final isSelected = _selectedIndex == idx;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFFFFFFF).withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isSelected
                    ? Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.3))
                    : null,
              ),
              child: ListTile(
                leading: Icon(icon, size: 20,
                    color: isSelected ? const Color(0xFFFFFFFF) : Colors.grey),
                title: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.grey)),
                trailing: badge > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9E9E9E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$badge',
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      )
                    : null,
                onTap: () {
                  setState(() => _selectedIndex = idx);
                  if (isDrawer) Navigator.pop(context);
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                dense: true,
              ),
            );
          }),
          const Spacer(),
          // Logout en el sidebar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ListTile(
              leading: const Icon(Icons.logout, size: 20, color: Colors.redAccent),
              title: const Text('Cerrar Sesión', style: TextStyle(fontSize: 13, color: Colors.redAccent)),
              onTap: () async {
                await ref.read(authServiceProvider).signOut();
                if (mounted) context.go('/login');
              },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              dense: true,
            ),
          ),
          // Footer con versión
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('HEIRLOG-TMS v1.0\npowered by Bitácora TMS',
                style: TextStyle(color: Colors.grey, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (_selectedIndex) {
        0 => const KpiDashboardView(key: ValueKey(0)),
        1 => const ControlTowerView(key: ValueKey(1)),
        2 => const ServiceRequestsInboxView(key: ValueKey(2)),
        3 => const AnalyticsView(key: ValueKey(3)),
        4 => const ZiyuConciliationView(key: ValueKey(4)),
        5 => const CotizadorScreen(key: ValueKey(5)),
        6 => const LiquidacionesAdminView(key: ValueKey(6)),
        7 => const RemuneracionesView(key: ValueKey(7)),
        8 => const ViaticosAdminView(key: ValueKey(8)),
        9 => const FlotaAdminView(key: ValueKey(9)),
        10 => const MantenimientoAdminView(key: ValueKey(10)),
        11 => const ConductoresView(key: ValueKey(11)),
        12 => const ConfigAdminView(key: ValueKey(12)),
        _ => const KpiDashboardView(key: ValueKey(0)),
      },
    );
  }
}

// ─── Vista de Conductores (con generador de códigos de invitación) ─────────────
// (Reimportada desde la versión anterior del admin_dashboard_screen.dart)

// Fin de AdminDashboardScreen
