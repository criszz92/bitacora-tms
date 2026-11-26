import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../trips/presentation/providers/trip_provider.dart';
import '../../../trips/domain/models/trip_model.dart';
import '../../../trips/domain/models/shift_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../admin/presentation/providers/admin_provider.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../../../trips/domain/services/distance_service.dart';
import '../../../admin/domain/models/incidencia_model.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../../admin/domain/models/service_request_model.dart';
import '../../../admin/domain/services/modogps_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../../admin/domain/models/infraestructura_vial_model.dart';
import '../../../../core/utils/road_infrastructure_detector.dart';
import '../../../../core/utils/route_live_monitor.dart';
import '../../../../core/services/silent_navigator_service.dart';
import '../../../admin/data/repositories/infraestructura_repository.dart';
import '../../../trips/domain/models/expense_model.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/widgets/app_update_dialog.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../trips/domain/services/fuzzy_search_service.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_container.dart';

class DriverDashboardScreen extends ConsumerWidget {
  const DriverDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mantener la app viva en segundo plano (Foreground Service) mientras haya una jornada activa
    ref.listen<AsyncValue<ShiftModel?>>(activeShiftProvider, (previous, next) {
      final shift = next.value;
      if (shift != null) {
        LocationService.startKeepAlive(
          title: 'Bitácora TMS - Jornada Activa',
          content: 'Camión: ${shift.patenteCamion} • Monitoreo Activo',
        );
      } else {
        LocationService.stopKeepAlive();
      }
    });

    // Comprobar silenciosamente si existe una nueva versión de la app y verificar servicio background
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final update = await AppUpdateService.checkForUpdate();
      if (update != null && context.mounted) {
        AppUpdateDialog.show(context, update);
      }
      final currentShift = ref.read(activeShiftProvider).value;
      if (currentShift != null) {
        LocationService.startKeepAlive(
          title: 'Bitácora TMS - Jornada Activa',
          content: 'Camión: ${currentShift.patenteCamion} • Monitoreo Activo',
        );
      }
    });

    // Escuchar servicios asignados en tiempo real y disparar notificación de alta prioridad
    ref.listen<AsyncValue<List<ServiceRequest>>>(assignedRequestsProvider, (previous, next) {
      final prevList = previous?.value ?? [];
      final currentList = next.value ?? [];
      if (currentList.isNotEmpty) {
        for (final req in currentList) {
          final isNew = !prevList.any((p) => p.id == req.id);
          if (isNew) {
            PushNotificationService.showCustomNotification(
              id: req.id.hashCode,
              title: '📦 ¡Nuevo Servicio Asignado!',
              body: '${req.clientName}: ${req.origin} -> ${req.destination}',
            );
          }
        }
      }
    });

    final activeShiftAsync = ref.watch(activeShiftProvider);
    final shiftTripsAsync = ref.watch(currentShiftTripsProvider);
    final hasActiveShift = activeShiftAsync.value != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background.withValues(alpha: 0.85),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasActiveShift ? AppColors.success : AppColors.warning,
                boxShadow: [
                  BoxShadow(
                    color: (hasActiveShift ? AppColors.success : AppColors.warning).withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 1.5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Bitácora Conductor',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 0.3,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (hasActiveShift ? AppColors.success : AppColors.textMuted).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (hasActiveShift ? AppColors.success : AppColors.textMuted).withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Text(
                hasActiveShift ? 'EN JORNADA' : 'CERRADA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: hasActiveShift ? AppColors.success : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
      drawer: _buildDriverDrawer(context, ref),
      body: Stack(
        children: [
          // Resplandor ambiental de cabina / instrumentación pesada (glow radial ámbar sutil al 6%)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.2),
                  radius: 0.85,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.06),
                    AppColors.backgroundSecondary.withValues(alpha: 0.4),
                    AppColors.background,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: activeShiftAsync.when(
              data: (shift) {
                if (shift == null) {
                  return _buildNoShiftView(context, ref);
                }
                // Listener para reportes automáticos de documentos
                _setupAutoDocumentReportListener(ref, shift);
                
                return _buildDashboardContent(context, ref, shiftTripsAsync, shift);
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (err, stack) => Center(
                child: Text('Error al cargar jornada: $err', style: const TextStyle(color: AppColors.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= PANTALLA DE BLOQUEO =================
  Widget _buildNoShiftView(BuildContext context, WidgetRef ref) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAssignedRequestBanner(context, ref), // Banner dinámico
            const SizedBox(height: 12),
            GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 26.0, vertical: 34.0),
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Emblema estilizado con halo ámbar
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.lock_clock_outlined,
                      size: 44,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Jornada Cerrada',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Para registrar viajes o viáticos, debes iniciar tu día de trabajo indicando el camión y el kilometraje.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.30),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => context.push('/start-shift'),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 28, color: AppColors.background),
                            SizedBox(width: 8),
                            Text(
                              'INICIAR JORNADA',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: AppColors.background,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= DRAWER (MENÚ LATERAL) =================
  Widget _buildDrawerItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: iconColor.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            )
          : null,
      onTap: onTap,
    );
  }

  Widget _buildDrawerSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDriverDrawer(BuildContext context, WidgetRef ref) {
    final user = ref.read(currentUserProfileProvider).value;
    final isAdmin = user?.rol == 'ADMIN';
    
    String displayName = 'Conductor';
    String initial = 'C';
    if (user != null && user.nombre.isNotEmpty) {
      final parts = user.nombre.trim().split(RegExp(r'\s+'));
      displayName = parts.length > 1 ? '${parts[0]} ${parts[1]}' : parts[0];
      initial = displayName[0].toUpperCase();
    }

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF11141B).withValues(alpha: 0.88),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Cabecera de Perfil con anillo degradado en ámbar
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.08),
                          AppColors.surfaceElevated.withValues(alpha: 0.6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: CircleAvatar(
                            backgroundColor: AppColors.surfaceElevated,
                            radius: 24,
                            child: Text(
                              initial,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                user?.email ?? 'Sin correo',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // SECCIÓN: OPERACIÓN EN RUTA
                  _buildDrawerSectionHeader('OPERACIÓN EN RUTA'),
                  _buildDrawerItem(
                    icon: Icons.local_gas_station_rounded,
                    iconColor: AppColors.warning,
                    title: 'Carga de Combustible',
                    onTap: () {
                      context.pop();
                      context.push('/add-expense?type=Combustible');
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.add_road_rounded,
                    iconColor: AppColors.info,
                    title: 'Peajes',
                    onTap: () {
                      context.pop();
                      context.push('/add-expense?type=Peaje');
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.receipt_long_rounded,
                    iconColor: AppColors.primaryWarm,
                    title: 'Rendición de Viáticos',
                    onTap: () {
                      context.pop();
                      context.push('/viaticos-request');
                    },
                  ),

                  Divider(color: Colors.white.withValues(alpha: 0.06), height: 20),

                  // SECCIÓN: GESTIÓN Y FLOTA
                  _buildDrawerSectionHeader('GESTIÓN Y FLOTA'),
                  _buildDrawerItem(
                    icon: Icons.radio_rounded,
                    iconColor: AppColors.primary,
                    title: 'Canal de Flota (PTT)',
                    subtitle: 'Avisos oficiales y radio de choferes',
                    onTap: () {
                      context.pop();
                      context.push('/fleet-chat');
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.badge_outlined,
                    iconColor: AppColors.primary,
                    title: 'Mi Perfil & Ficha',
                    subtitle: 'Licencia, documentos y puntaje',
                    onTap: () {
                      context.pop();
                      context.push('/driver-profile');
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.analytics_outlined,
                    iconColor: const Color(0xFF60A5FA),
                    title: 'Resumen del Mes',
                    subtitle: 'Viajes, viáticos y comisiones',
                    onTap: () {
                      context.pop();
                      context.push('/monthly-summary');
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.build_circle_outlined,
                    iconColor: AppColors.primaryWarm,
                    title: 'Salud del Camión',
                    subtitle: 'Mantenimiento y documentos',
                    onTap: () {
                      context.pop();
                      _showVehicleMaintenanceDialog(context, ref);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.history_rounded,
                    iconColor: AppColors.textSecondary,
                    title: 'Agregar Viaje Pasado',
                    subtitle: 'Olvidé registrar un viaje',
                    onTap: () {
                      context.pop();
                      context.push('/retro-trip');
                    },
                  ),

                  Divider(color: Colors.white.withValues(alpha: 0.06), height: 20),

                  // SECCIÓN: SISTEMA
                  _buildDrawerSectionHeader('SISTEMA'),
                  _buildDrawerItem(
                    icon: Icons.notifications_active_rounded,
                    iconColor: AppColors.primary,
                    title: 'Probar Alerta & Sonido',
                    subtitle: 'Verificar altavoz y canal binaural',
                    onTap: () async {
                      context.pop();
                      final result = await PushNotificationService.testAlertNotification();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result.message),
                            backgroundColor: result.success
                                ? (result.isWeb ? Colors.blueAccent : const Color(0xFF2E7D32))
                                : Colors.amber.shade900,
                            duration: Duration(seconds: result.isWeb ? 7 : 4),
                            action: result.isWeb
                                ? SnackBarAction(
                                    label: 'DESCARGAR APK',
                                    textColor: Colors.amberAccent,
                                    onPressed: () => launchUrl(
                                      Uri.parse('https://github.com/criszz92/bitacora-tms/releases/download/v1.1.0/bitacora-tms-v1.1.0.apk'),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                  )
                                : null,
                          ),
                        );
                      }
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.system_update_alt_rounded,
                    iconColor: AppColors.success,
                    title: 'Buscar Actualizaciones',
                    subtitle: 'Verificar versión del sistema',
                    onTap: () async {
                      context.pop();
                      final update = await AppUpdateService.checkForUpdate(ignorePostponed: true);
                      if (context.mounted) {
                        if (update != null) {
                          AppUpdateDialog.show(context, update);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Tienes la última versión instalada.'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      }
                    },
                  ),

                  if (isAdmin) ...[
                    Divider(color: Colors.white.withValues(alpha: 0.06), height: 20),
                    _buildDrawerSectionHeader('ADMINISTRACIÓN'),
                    _buildDrawerItem(
                      icon: Icons.admin_panel_settings_outlined,
                      iconColor: AppColors.primary,
                      title: 'Volver a Administración',
                      titleColor: AppColors.primary,
                      onTap: () {
                        context.pop();
                        context.go('/admin');
                      },
                    ),
                  ],

                   const SizedBox(height: 16),
                  // Tarjeta informativa de plataforma
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kIsWeb ? Colors.blue.withValues(alpha: 0.08) : Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kIsWeb ? Colors.blueAccent.withValues(alpha: 0.25) : Colors.greenAccent.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                kIsWeb ? Icons.language_rounded : Icons.android_rounded,
                                size: 16,
                                color: kIsWeb ? Colors.blueAccent : Colors.greenAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  kIsWeb ? 'Acceso Web / PWA' : 'APK Nativa Android',
                                  style: TextStyle(
                                    color: kIsWeb ? Colors.blueAccent : Colors.greenAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'v1.1.0',
                                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            kIsWeb
                                ? 'Estás conectado desde el navegador. Para habilitar GPS continuo en segundo plano y alertas con altavoz, instala la APK.'
                                : 'Instalación nativa con motor GPS en segundo plano y alertas prioritarias activas.',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          if (kIsWeb) ...[
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => launchUrl(
                                Uri.parse('https://github.com/criszz92/bitacora-tms/releases/download/v1.1.0/bitacora-tms-v1.1.0.apk'),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.download_for_offline_rounded, size: 14, color: Colors.amberAccent),
                                  SizedBox(width: 6),
                                  Text(
                                    'Descargar APK Nativo Oficial ➔',
                                    style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.30),
                          width: 0.8,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.logout_rounded, color: AppColors.error),
                        title: const Text(
                          'Cerrar Sesión',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        onTap: () async {
                          context.pop();
                          await ref.read(authServiceProvider).signOut();
                          if (context.mounted) context.go('/login');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================= DASHBOARD REAL MÓVIL =================
  Widget _buildDashboardContent(BuildContext context, WidgetRef ref, AsyncValue<List<TripModel>> shiftTripsAsync, ShiftModel shift) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildExpirationBanner(ref),
          _buildAssignedRequestBanner(context, ref), // Banner dinámico
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tus Registros',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.directions_bus_rounded, size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Camión asignado: ${shift.patenteCamion}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  final completed = shiftTripsAsync.value?.where((t) => t.status != 'En Ruta').toList() ?? [];
                  _showEndShiftDialog(context, ref, shift, completedTrips: completed);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_circle_rounded, color: AppColors.error, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Cerrar Jornada',
                        style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          shiftTripsAsync.when(
            data: (trips) {
              final activeCount = trips.where((t) => t.status == 'En Ruta').length;
              final completedTrips = trips.where((t) => t.status != 'En Ruta').toList();
              final double totalKmJornada = completedTrips.fold(0.0, (acc, t) => acc + (t.totalKm ?? 0.0));
              return GlassContainer(
                borderRadius: BorderRadius.circular(14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_shipping_rounded,
                      size: 16,
                      color: activeCount > 0 ? AppColors.success : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$activeCount',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 4),
                    Text(activeCount == 1 ? 'Activo' : 'Activos', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 16, color: Colors.white12),
                    const SizedBox(width: 12),
                    const Icon(Icons.route_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      '${totalKmJornada.toStringAsFixed(0)} KM',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('Jornada', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    const Spacer(),
                    InkWell(
                      onTap: () => _showReportIncidentDialog(context, ref, shift),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.35), width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.report_problem_outlined, size: 13, color: AppColors.error),
                            SizedBox(width: 4),
                            Text('Incidencia', style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => Container(height: 38, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12))),
            error: (err, stack) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Viajes de la Jornada',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.2,
                ),
              ),
              shiftTripsAsync.maybeWhen(
                data: (trips) {
                  final hasActive = trips.any((t) => t.status == 'En Ruta');
                  if (!hasActive) return const SizedBox.shrink();
                  return TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _showStartMovementOptions(context),
                    icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                    label: const Text('Nuevo Movimiento', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shiftTripsAsync.when(
              data: (trips) {
                if (trips.isEmpty) {
                  return const Center(
                    child: Text('No hay viajes registrados en esta jornada', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                final sorted = List<TripModel>.from(trips)..sort((a, b) {
                  if (a.status == 'En Ruta' && b.status != 'En Ruta') return -1;
                  if (a.status != 'En Ruta' && b.status == 'En Ruta') return 1;
                  return b.startDate.compareTo(a.startDate);
                });
                return ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    return _buildTripCard(context, ref, sorted[index], shift.patenteCamion);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (error, _) => Center(child: Text('Error: $error', style: const TextStyle(color: AppColors.error))),
            ),
          ),
          // Botón inferior: solo se muestra destacado si NO hay viaje activo para no tapar la pantalla
          shiftTripsAsync.maybeWhen(
            data: (trips) {
              final hasActive = trips.any((t) => t.status == 'En Ruta');
              if (hasActive) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _showStartMovementOptions(context),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_box_rounded, color: AppColors.background, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'INICIAR NUEVA ACTIVIDAD',
                              style: TextStyle(
                                color: AppColors.background,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _showStartMovementOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E222B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Selecciona el Tipo de Movimiento',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Elige si inicias un servicio comercial o un desplazamiento sin ganancias.',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _buildMovementOptionTile(
                ctx,
                icon: Icons.local_shipping,
                color: Colors.greenAccent,
                title: 'Viaje Operativo (Comercial)',
                subtitle: 'Flete con cliente y tarifa. Suma comisión y viáticos según corresponda.',
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/add-trip?tipo=operativo');
                },
              ),
              const SizedBox(height: 12),
              _buildMovementOptionTile(
                ctx,
                icon: Icons.inventory_2_outlined,
                color: Colors.amberAccent,
                title: 'Retiro Anticipado (Sin Ganancia)',
                subtitle: 'Desplazamiento previo a faena o depósito. Registra KM y peajes sin comisión ni viático.',
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/add-trip?tipo=retiro_anticipado');
                },
              ),
              const SizedBox(height: 12),
              _buildMovementOptionTile(
                ctx,
                icon: Icons.build_circle_outlined,
                color: Colors.cyanAccent,
                title: 'Traslado a Mantenimiento',
                subtitle: 'Movimiento de camión a taller o revisión técnica. Sin ganancias (\$0).',
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/add-trip?tipo=traslado_mantenimiento');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMovementOptionTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161A22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }

  // ================= ALERTAS DE DOCUMENTACIÓN =================

  Widget _buildExpirationBanner(WidgetRef ref) {
    final vehicleAsync = ref.watch(currentVehicleProvider);
    
    return vehicleAsync.when(
      data: (vehicle) {
        if (vehicle == null || !vehicle.hasExpiringDocs) return const SizedBox.shrink();
        
        final expiring = vehicle.getExpiringDocuments(7);
        final hasCritical = expiring.any((d) => d['esCritico'] as bool);
        
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hasCritical ? Colors.redAccent.withValues(alpha: 0.1) : Colors.orangeAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hasCritical ? Colors.redAccent : Colors.orangeAccent, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(hasCritical ? Icons.error_outline : Icons.warning_amber_rounded, 
                       color: hasCritical ? Colors.redAccent : Colors.orangeAccent, size: 20),
                  const SizedBox(width: 12),
                  const Text('ALERTA DE DOCUMENTACIÓN', 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
                ],
              ),
              const SizedBox(height: 8),
              ...expiring.map((doc) => Padding(
                padding: const EdgeInsets.only(left: 32, bottom: 4),
                child: Text(
                  '${doc['nombre']}: vence en ${doc['diasRestantes']} días (${DateFormat('dd/MM').format(doc['fecha'])})',
                  style: TextStyle(color: hasCritical ? Colors.redAccent : Colors.orangeAccent, fontSize: 12),
                ),
              )),
              const SizedBox(height: 8),
              const Text('Favor dar aviso manual a jefatura lo antes posible.', 
                style: TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic)),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  void _setupAutoDocumentReportListener(WidgetRef ref, ShiftModel shift) {
    // Escuchamos el vehículo actual para detectar cambios en documentos
    ref.listen(currentVehicleProvider, (previous, next) {
      final vehicle = next.value;
      if (vehicle == null) return;

      final criticalDocs = vehicle.getExpiringDocuments(1); // 1 día o menos
      if (criticalDocs.isEmpty) return;

      // Generamos un reporte automático por cada documento crítico
      for (final doc in criticalDocs) {
        _triggerAutoReport(ref, shift, vehicle, doc['nombre'] as String, doc['diasRestantes'] as int);
      }
    });
  }

  void _triggerAutoReport(WidgetRef ref, ShiftModel shift, VehicleModel vehicle, String docName, int days) async {
    final user = ref.read(currentUserProfileProvider).value;
    if (user == null) return;

    final id = const Uuid().v4();
    final descripcion = 'SISTEMA: Alerta automática - El documento "$docName" ${days < 0 ? "ESTÁ VENCIDO" : (days == 0 ? "VENCE HOY" : "VENCE MAÑANA")}. '
                        'Favor gestionar renovación urgente.';

    final incidencia = IncidenciaModel(
      id: id,
      idEmpresa: shift.idEmpresa,
      idChofer: user.uid,
      choferNombre: user.nombre,
      vehicleId: vehicle.id,
      vehiclePatente: vehicle.patente,
      tipo: 'Documentos',
      descripcion: descripcion,
      fecha: DateTime.now(),
      estado: 'Pendiente',
    );

    await ref.read(tripRepositoryProvider).reportIncidencia(incidencia);
  }

  // ================= MANTENIMIENTO DIALOGS =================
  void _showVehicleMaintenanceDialog(BuildContext context, WidgetRef ref) async {
    final activeShift = ref.read(activeShiftProvider).value;
    if (activeShift == null) return;

    // Fetch vehicles from repository instead of relying on an uninitialized provider
    final vehicles = await ref.read(adminRepositoryProvider).watchVehicles(activeShift.idEmpresa).first;
    
    VehicleModel? vehicle;
    for (var v in vehicles) {
      if (v.patente == activeShift.patenteCamion) {
        vehicle = v;
        break;
      }
    }

    if (!context.mounted) return;

    if (vehicle == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontró información del camión')));
      return;
    }

    final nextService = vehicle.nextOilChangeKm ?? 0.0;
    final remaining = nextService - vehicle.currentOdometer;
    
    final v = vehicle; // Safe non-nullable reference for the closure

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Estado: ${v.patente}', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Kilometraje Actual', '${NumberFormat('#,###').format(v.currentOdometer)} km'),
            _buildInfoRow('Próximo Servicio', '${NumberFormat('#,###').format(nextService)} km'),
            const Divider(color: Colors.white10, height: 24),
            _buildInfoRow('Mantenimiento', remaining > 0 ? '${NumberFormat('#,###').format(remaining)} km restantes' : 'VENCIDO', color: remaining > 500 ? Colors.greenAccent : Colors.redAccent),
            const Divider(color: Colors.white10, height: 24),
            _buildDateRow('Revisión Técnica', v.rtExpirationDate),
            _buildDateRow('SOAP', v.soapExpirationDate),
            _buildDateRow('Permiso Circulación', v.permisoExpirationDate),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _showReportIncidentDialog(BuildContext context, WidgetRef ref, ShiftModel shift) {
    final user = ref.read(currentUserProfileProvider).value;
    final descCtrl = TextEditingController();
    String? selectedType;
    final types = ['Mecánica', 'Neumáticos', 'Documentos', 'Otros'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Reportar Incidencia', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Tipo de Problema', labelStyle: TextStyle(color: Colors.grey)),
                items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => selectedType = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Descripción breve',
                  labelStyle: TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.black26,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: selectedType == null ? null : () async {
                final vehicles = ref.read(vehiclesProvider).value ?? [];
                final matchedVehicle = vehicles.where((v) => v.patente == shift.patenteCamion).firstOrNull;
                final vehicleDocId = matchedVehicle?.id ?? '';

                final incidencia = IncidenciaModel(
                  id: const Uuid().v4(),
                  idEmpresa: shift.idEmpresa,
                  vehicleId: vehicleDocId,
                  vehiclePatente: shift.patenteCamion,
                  idChofer: shift.idChofer,
                  choferNombre: user?.nombre ?? 'Conductor',
                  tipo: selectedType!,
                  descripcion: descCtrl.text,
                  fecha: DateTime.now(),
                );
                try {
                  await ref.read(tripRepositoryProvider).reportIncidencia(incidencia);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reporte enviado correctamente')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al enviar: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Enviar Reporte'),
            ),
          ],
        ),
      ),
    );
  }

  // ================= AUXILIARES =================
  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDateRow(String label, DateTime? date) {
    final isExpired = date != null && date.isBefore(DateTime.now());
    return _buildInfoRow(label, date != null ? DateFormat('dd/MM/yyyy').format(date) : 'No cargado', color: isExpired ? Colors.redAccent : null);
  }



  Widget _buildTripCard(BuildContext context, WidgetRef ref, TripModel trip, String defaultPlate) {
    final isEnRuta = trip.status == 'En Ruta';
    final targetPlate = trip.vehicleId ?? defaultPlate;
    final gpsUnitAsync = ref.watch(singleVehicleGpsProvider(targetPlate));

    if (isEnRuta) {
      ref.watch(silentNavigatorObserverProvider(targetPlate));
      return _buildActiveTripCard(context, ref, trip, targetPlate, gpsUnitAsync);
    } else {
      return _buildCompletedTripCard(context, ref, trip, targetPlate);
    }
  }

  Widget _buildActiveTripCard(
    BuildContext context,
    WidgetRef ref,
    TripModel trip,
    String targetPlate,
    AsyncValue<GpsUnit?> gpsUnitAsync,
  ) {
    final nextHito = _getNextHito(trip.hitoActual);
    final pendingArrival = ref.watch(pendingArrivalProvider);

    return GlassContainer(
      isActive: true,
      margin: const EdgeInsets.only(bottom: 12),
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14.0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header del viaje activo
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: trip.isRetiroAnticipado 
                        ? const Color(0xFFFBBF24) 
                        : (trip.isMantenimiento ? const Color(0xFF38BDF8) : const Color(0xFF22C55E)),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  trip.isRetiroAnticipado
                      ? 'RETIRO ANTICIPADO'
                      : (trip.isMantenimiento ? 'MANTENIMIENTO' : 'VIAJE EN CURSO'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: trip.isRetiroAnticipado 
                        ? const Color(0xFFFBBF24) 
                        : (trip.isMantenimiento ? const Color(0xFF38BDF8) : const Color(0xFF4ADE80)),
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                if (!trip.isOperativo) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: const Text('SIN GANANCIAS', style: TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
                const Spacer(),
                if (trip.containerNumber != null && trip.containerNumber!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2, size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          trip.containerNumber!,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                else if (trip.guideNumber != null && trip.guideNumber!.isNotEmpty)
                  Text('Guía: ${trip.guideNumber}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(width: 8),
                Text(
                  DateFormat('HH:mm').format(trip.startDate),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── ALERTA PROACTIVA DE LLEGADA DETECTADA POR GEOCERCA ──
            if (pendingArrival != null && pendingArrival.tripId == trip.id) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F5132).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.greenAccent, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '¡Llegada Detectada: ${pendingArrival.destino}!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('GEOCERCA GPS', style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'El camión ingresó a ${pendingArrival.geocerca ?? pendingArrival.destino} a las ${DateFormat('HH:mm').format(pendingArrival.detectedAt)}. Confirma para registrar tu hora real y avanzar al siguiente tramo.',
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.done_all, size: 18),
                        label: Text(
                          'CONFIRMAR LLEGADA A ${pendingArrival.destino.toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                        onPressed: () async {
                          await ref.read(silentNavigatorServiceProvider).confirmLegArrival(
                                trip: trip,
                                tramoId: pendingArrival.tramoId,
                              );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✓ Llegada a ${pendingArrival.destino} confirmada exitosamente'),
                                backgroundColor: const Color(0xFF1E3A8A),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── MISIÓN SEGMENTADA (BARRA DE TRAMOS EN SEGUNDO PLANO) ──
            if (trip.tramos != null && trip.tramos!.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.alt_route, color: Colors.cyanAccent, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Misión Segmentada (Navegador Silencioso)',
                          style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                        const Spacer(),
                        Text(
                          'Tramo ${trip.tramoActualIndex + 1} de ${trip.tramos!.length}',
                          style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (int i = 0; i < trip.tramos!.length; i++) ...[
                          Expanded(
                            child: Builder(
                              builder: (ctx) {
                                final tr = trip.tramos![i];
                                final isDone = tr['estado'] == 'completado';
                                final isCurrent = tr['estado'] == 'en_ruta';
                                final color = isDone
                                    ? Colors.greenAccent
                                    : (isCurrent ? Colors.cyanAccent : Colors.white24);

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: color.withValues(alpha: 0.5)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            isDone
                                                ? Icons.check_circle
                                                : (isCurrent ? Icons.play_arrow : Icons.radio_button_unchecked),
                                            size: 12,
                                            color: color,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              tr['tipo'] == 'posicionamiento_vacio'
                                                  ? 'T1: Vacío'
                                                  : (tr['tipo'] == 'cargado' ? 'T2: Cargado' : 'Intermedio'),
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        tr['destino'] ?? '',
                                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          if (i < trip.tramos!.length - 1)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4.0),
                              child: Icon(Icons.arrow_forward_ios, size: 10, color: Colors.white24),
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // ── MONITOREO DE RUTA EN VIVO (Alertas de Romanas, Restricciones y Peajes) ──
            Builder(
              builder: (ctx) {
                final monitorState = ref.watch(routeMonitorStreamProvider(targetPlate)).value ?? RouteMonitorState();
                if (monitorState.activeAlerts.isEmpty && monitorState.passedTolls.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  children: [
                    // Alertas activas prioritarias (Romanas o Restricciones Horarias)
                    ...monitorState.activeAlerts.take(2).map((alert) {
                      final isRomana = alert.tipo == TipoPuntoInfraestructura.romana;
                      final isRestriccion = alert.tipo == TipoPuntoInfraestructura.restriccion;
                      final alertColor = isRomana ? Colors.amberAccent : (isRestriccion ? Colors.redAccent : Colors.cyanAccent);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: alertColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: alertColor.withValues(alpha: 0.6), width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Icon(isRomana ? Icons.balance : (isRestriccion ? Icons.block : Icons.toll), color: alertColor, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(alert.title, style: TextStyle(color: alertColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                  Text(alert.message, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    // Acumulador de peajes detectados en vivo en ruta
                    if (monitorState.passedTolls.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.toll_outlined, color: Colors.tealAccent, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Peajes cruzados: ${monitorState.passedTolls.length} • Estimado: \$${monitorState.estimatedTollsTotal.toInt()}',
                                style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),

            // Telemetría GPS en vivo / Geocerca detectada
            gpsUnitAsync.when(
              data: (unit) {
                if (unit == null) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.satellite_alt, size: 12, color: Colors.white38),
                        SizedBox(width: 6),
                        Text('Sincronizando con ModoGPS...', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  );
                }

                final inGeofence = unit.currentGeofence != null && unit.currentGeofence!.isNotEmpty;
                final isIdle = unit.isRalenti;

                if (isIdle) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.6), width: 0.8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.pause_circle_outline, size: 14, color: Colors.amberAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            inGeofence
                                ? 'Motor en Ralentí • En ${unit.currentGeofence}'
                                : 'Motor Encendido Detenido • Modo Ralentí (0 km/h)',
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (inGeofence) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F5132).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5), width: 0.8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Colors.greenAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            unit.isEngineOff
                                ? 'En ${unit.currentGeofence} • Motor Apagado'
                                : 'Geocerca GPS: ${unit.currentGeofence}',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  final isRalenti = unit.isRalenti;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isRalenti 
                          ? Colors.orange.withValues(alpha: 0.2) 
                          : const Color(0xFF1E3A8A).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isRalenti ? Colors.orangeAccent.withValues(alpha: 0.6) : Colors.blueAccent.withValues(alpha: 0.4), 
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isRalenti ? Icons.hourglass_top_rounded : Icons.satellite_alt, 
                          size: 13, 
                          color: isRalenti ? Colors.orangeAccent : Colors.lightBlueAccent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isRalenti
                                ? 'Motor Encendido • Modo Ralentí (0 km/h) • Cuidado Turbo'
                                : (unit.speed > 2.0
                                    ? 'GPS Conectado • En Ruta (${unit.speed.toStringAsFixed(0)} km/h)'
                                    : 'GPS Conectado • Detenido (Motor Apagado)'),
                            style: TextStyle(
                              color: isRalenti ? Colors.orangeAccent : const Color(0xFF93C5FD), 
                              fontSize: 11.5, 
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 10),

            // Trazado de Ruta Completa: Origen ➔ Cliente/Planta ➔ Puerto/Depósito
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.radio_button_checked, size: 14, color: Colors.greenAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          trip.origin,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6.5, top: 2, bottom: 2),
                    child: Row(
                      children: [
                        Container(width: 1.5, height: 16, color: Colors.white24),
                        const SizedBox(width: 14),
                        const Icon(Icons.business_outlined, size: 12, color: Colors.cyanAccent),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Carga: ${trip.client}',
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trip.paradasIntermedias != null && trip.paradasIntermedias!.isNotEmpty)
                    for (final stop in trip.paradasIntermedias!)
                      Padding(
                        padding: const EdgeInsets.only(left: 6.5, top: 2, bottom: 2),
                        child: Row(
                          children: [
                            Container(width: 1.5, height: 16, color: Colors.white24),
                            const SizedBox(width: 14),
                            const Icon(Icons.alt_route, size: 12, color: Colors.amberAccent),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Parada: $stop',
                                style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          trip.puntoDescarga ?? trip.destination,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Hito Operativo Actual y Avance Rápido (1 solo toque)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flag_rounded, size: 15, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Hito: ${trip.hitoActual ?? "En Tránsito Inicial"}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trip.hitos != null && trip.hitos!.isNotEmpty)
                        Text('${trip.hitos!.length} reg.', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            await ref.read(tripRepositoryProvider).registrarHito(trip.id, nextHito);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ Hito avanzado a: "$nextHito"'),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: const Color(0xFF1E3A8A),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.fast_forward_rounded, size: 15),
                          label: Text(
                            'Avanzar: $nextHito',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.all(8),
                          minimumSize: const Size(36, 36),
                        ),
                        icon: const Icon(Icons.more_horiz, size: 18, color: Colors.white70),
                        tooltip: 'Ver lista completa de hitos',
                        onPressed: () => _showChangeHitoModal(context, ref, trip),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '🤖 ModoGPS detecta paradas automáticamente por satélite.',
                    style: TextStyle(color: Colors.white38, fontSize: 9.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Botones de Acción: FINALIZAR VIAJE + Trazado GPS
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    onPressed: () => _showEndTripDialog(context, ref, trip, targetPlate),
                    icon: const Icon(Icons.check_circle, color: Colors.black, size: 18),
                    label: const Text(
                      'FINALIZAR VIAJE',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.lightBlueAccent,
                    side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showTripGpsComparisonDialog(context, ref, trip, targetPlate),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.satellite_alt_outlined, size: 16),
                      SizedBox(width: 4),
                      Text('GPS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }

  Widget _buildCompletedTripCard(BuildContext context, WidgetRef ref, TripModel trip, String targetPlate) {
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                trip.isRetiroAnticipado
                    ? 'RETIRO ANTICIPADO'
                    : (trip.isMantenimiento ? 'MANTENIMIENTO' : 'VIAJE COMPLETADO'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: trip.isRetiroAnticipado
                      ? AppColors.primary
                      : (trip.isMantenimiento ? AppColors.info : AppColors.textSecondary),
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                children: [
                  if (!trip.isOperativo)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('SIN GANANCIAS', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 0.8),
                    ),
                    child: Text(
                      trip.status,
                      style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 16, color: Colors.white12),
          _buildRouteRow(Icons.my_location, 'Origen', trip.origin),
          const SizedBox(height: 8),
          _buildRouteRow(Icons.location_on, 'Destino', trip.destination),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.inventory_2, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  trip.containerNumber != null && trip.containerNumber!.isNotEmpty
                      ? trip.containerNumber!
                      : (trip.guideNumber != null && trip.guideNumber!.isNotEmpty
                          ? 'Guía: ${trip.guideNumber}'
                          : 'Carga Suelta'),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trip.totalKm != null) ...[
                const Icon(Icons.route_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  '${trip.totalKm!.toStringAsFixed(1)} KM',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () => _showEditTripDriverDialog(context, ref, trip),
              icon: const Icon(Icons.edit, size: 15),
              label: const Text('EDITAR KM / GUÍA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  String _getNextHito(String? current) {
    if (current == null) return 'En Faena (Carga / Retiro)';
    final c = current.toLowerCase();
    if (c.contains('base') || c.contains('inicial') || c.contains('tránsito a puerto')) {
      return 'En Faena (Carga / Retiro)';
    } else if (c.contains('faena') || c.contains('antepuerto') || c.contains('retiro') || c.contains('puerto')) {
      return 'En Ruta a Destino';
    } else if (c.contains('ruta a destino') || c.contains('tránsito a cliente') || c.contains('cliente 1')) {
      return 'Llegada a Destino (Descarga)';
    } else if (c.contains('llegada') || c.contains('destino') || c.contains('descarga') || c.contains('devolución')) {
      return 'Retorno a Base / Cierre';
    }
    return 'En Faena (Carga / Retiro)';
  }

  Future<void> _showChangeHitoModal(BuildContext context, WidgetRef ref, TripModel trip) async {
    final macroHitos = [
      {'nombre': 'En Tránsito Inicial / A Carga', 'icon': Icons.directions_bus_outlined, 'desc': 'Traslado inicial hacia punto de retiro o faena'},
      {'nombre': 'En Faena / Carga / Operación', 'icon': Icons.storefront_outlined, 'desc': 'En cliente o terminal cargando o realizando faena'},
      {'nombre': 'En Ruta a Destino', 'icon': Icons.route_outlined, 'desc': 'Viaje por carretera con carga hacia destino final'},
      {'nombre': 'Llegada a Destino (Descarga)', 'icon': Icons.done_all_rounded, 'desc': 'En planta de descarga o entrega de contenedor'},
    ];

    final hitosDetallados = [
      {'nombre': 'En Base (Preparación)', 'icon': Icons.home_work_outlined},
      {'nombre': 'En Antepuerto (Espera / Stacking)', 'icon': Icons.hourglass_top_rounded},
      {'nombre': 'En Puerto / Depósito (Retiro de Vacío)', 'icon': Icons.archive_outlined},
      {'nombre': 'En Cliente 2 (Consolidación / Punto Adicional)', 'icon': Icons.add_business_outlined},
      {'nombre': 'En Puerto / Depósito (Entrega de Contenedor)', 'icon': Icons.unarchive_outlined},
      {'nombre': 'Retorno a Base / Cierre de Ciclo', 'icon': Icons.home_rounded},
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E222B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  const SizedBox(height: 14),
                  const Text(
                    'Hito Operativo de Ruta',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: Colors.lightBlueAccent),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ModoGPS detecta paradas y geocercas satelitalmente sin necesidad de ingreso manual.',
                            style: TextStyle(color: Colors.lightBlueAccent, fontSize: 10.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'ETAPAS PRINCIPALES (RECOMENDADO):',
                    style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  ...macroHitos.map((item) {
                    final isSelected = trip.hitoActual == item['nombre'];
                    return ListTile(
                      dense: true,
                      leading: Icon(item['icon'] as IconData, color: isSelected ? Colors.greenAccent : Colors.white70),
                      title: Text(
                        item['nombre'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.greenAccent : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        item['desc'] as String,
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18) : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await ref.read(tripRepositoryProvider).registrarHito(trip.id, item['nombre'] as String);
                      },
                    );
                  }),
                  const Divider(color: Colors.white12, height: 20),
                  const Text(
                    'HITOS ESPECÍFICOS DE PUERTO / FAENA:',
                    style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 4),
                  ...hitosDetallados.map((item) {
                    final isSelected = trip.hitoActual == item['nombre'];
                    return ListTile(
                      dense: true,
                      leading: Icon(item['icon'] as IconData, size: 18, color: isSelected ? Colors.amber : Colors.white60),
                      title: Text(
                        item['nombre'] as String,
                        style: TextStyle(color: isSelected ? Colors.amber : Colors.white70, fontSize: 12),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.amber, size: 16) : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await ref.read(tripRepositoryProvider).registrarHito(trip.id, item['nombre'] as String);
                      },
                    );
                  }),
                  const Divider(color: Colors.white12, height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13161C),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.alt_route, size: 16, color: Colors.blueAccent),
                            SizedBox(width: 8),
                            Text(
                              'Gestión de Ruta en Curso',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '¿Hubo un cambio de planes o desvío imprevisto? Puedes agregar una parada intermedia y la misión satelital se reestructurará en tiempo real.',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                            label: const Text('AGREGAR PARADA INTERMEDIA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showAddIntermediateStopDialog(context, ref, trip);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddIntermediateStopDialog(
    BuildContext context,
    WidgetRef ref,
    TripModel trip,
  ) async {
    final stopCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E222B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.alt_route, color: Colors.blueAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Agregar Parada Intermedia',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ingresa el punto o faena que visitarás antes de llegar al destino final. La misión satelital actualizará los tramos.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Autocomplete<String>(
                      initialValue: stopCtrl.value,
                      optionsBuilder: (TextEditingValue textValue) {
                        final query = textValue.text.trim();
                        if (query.isEmpty) return const [];
                        return ref.read(fuzzySearchProvider).search(query);
                      },
                      onSelected: (String selection) {
                        stopCtrl.text = selection;
                      },
                      fieldViewBuilder: (fCtx, innerCtrl, focusNode, onEditingComplete) {
                        innerCtrl.addListener(() {
                          if (stopCtrl.text != innerCtrl.text) {
                            stopCtrl.value = innerCtrl.value;
                          }
                        });
                        return TextField(
                          controller: innerCtrl,
                          focusNode: focusNode,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Punto / Planta / Romana',
                            labelStyle: const TextStyle(color: Colors.white60),
                            hintText: 'Ej: FORSAC, ORIZON, BASE...',
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF13161C),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(Icons.add_location, color: Colors.blueAccent),
                          ),
                        );
                      },
                    ),
                    if (trip.paradasIntermedias != null && trip.paradasIntermedias!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Paradas actuales ya registradas:',
                        style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      ...trip.paradasIntermedias!.map(
                        (p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            children: [
                              const Icon(Icons.check, size: 12, color: Colors.greenAccent),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(p, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final stopText = stopCtrl.text.trim();
                          if (stopText.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Por favor escribe o selecciona un punto'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          try {
                            await ref.read(tripRepositoryProvider).addIntermediateStopToActiveTrip(
                                  tripId: trip.id,
                                  stopName: stopText,
                                  currentTrip: trip,
                                );
                            if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ Parada agregada: $stopText. Misión satelital reestructurada.'),
                                  backgroundColor: const Color(0xFF2E7D32),
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('AGREGAR Y REESTRUCTURAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showTripGpsComparisonDialog(
    BuildContext context,
    WidgetRef ref,
    TripModel trip,
    String plate,
  ) async {
    final modoGps = ref.read(modoGpsServiceProvider);
    final startTime = trip.startDate;
    final endTime = trip.endDate ?? DateTime.now();
    final timeFmt = DateFormat('HH:mm');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.satellite_alt, color: Colors.blueAccent, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Comparativa GPS de Tramo', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Cruce exacto fecha y hora con ModoGPS', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: FutureBuilder<GpsHistoricalTrip?>(
          future: modoGps.fetchTripInterval(
            plate: plate,
            startTime: startTime,
            endTime: endTime,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 180,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.blueAccent),
                      SizedBox(height: 16),
                      Text('Consultando recorrido exacto en ModoGPS...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
              return SizedBox(
                height: 140,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 36),
                      const SizedBox(height: 10),
                      Text(
                        'No se encontraron puntos GPS para este rango horario (${timeFmt.format(startTime)} - ${timeFmt.format(endTime)}).',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }

            final hTrip = snapshot.data!;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Text(
                          '${timeFmt.format(startTime)} ➔ ${timeFmt.format(endTime)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const Spacer(),
                        Text('Placa: ${hTrip.plate}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          'KM GPS',
                          '${hTrip.totalDistanceKm.toStringAsFixed(1)} KM',
                          Icons.straighten,
                          Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMetricTile(
                          'KM Registrados',
                          trip.totalKm != null ? '${trip.totalKm!.toStringAsFixed(1)} KM' : 'Sin reg.',
                          Icons.route,
                          Colors.purpleAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          'Vel. Promedio',
                          '${hTrip.avgSpeed.toStringAsFixed(0)} km/h',
                          Icons.speed,
                          Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMetricTile(
                          'Vel. Máxima',
                          '${hTrip.maxSpeed.toStringAsFixed(0)} km/h',
                          Icons.trending_up,
                          Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Hitos y Geocercas Detectadas:',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (hTrip.stays.isEmpty)
                    const Text('No se registraron paradas dentro de geocercas en este intervalo.', style: TextStyle(color: Colors.white38, fontSize: 11))
                  else
                    ...hTrip.stays.map((stay) => Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, size: 14, color: Colors.greenAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(stay.geofenceName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            Text(
                              '${timeFmt.format(stay.entryTime)} - ${timeFmt.format(stay.exitTime)} (${stay.durationMinutes}m)',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    )),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
                Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEndTripDialog(BuildContext context, WidgetRef ref, TripModel trip, String targetPlate) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EndTripDialog(trip: trip, targetPlate: targetPlate),
    );
  }

  Future<void> _showEditTripDriverDialog(BuildContext context, WidgetRef ref, TripModel trip) async {
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

  Future<void> _showEndShiftDialog(
    BuildContext context, 
    WidgetRef ref, 
    ShiftModel shift, {
    List<TripModel>? completedTrips,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EndShiftDialog(
        shift: shift,
        completedTrips: completedTrips ?? [],
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }

  // ================= BANNER DE ASIGNACIÓN IA =================

  Widget _buildAssignedRequestBanner(BuildContext context, WidgetRef ref) {
    final assignedAsync = ref.watch(assignedRequestsProvider);

    return assignedAsync.when(
      data: (requests) {
        if (requests.isEmpty) return const SizedBox.shrink();
        
        final ServiceRequest request = requests.first;
        final shift = ref.read(activeShiftProvider).value;
        final hasShift = shift != null;
        
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.stars, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'SOLICITUD DE ${request.clientName.toUpperCase()}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 12),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${request.origin} → ${request.destination}',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (!hasShift) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠ Tienes un servicio asignado. Para verlo debes INICIAR JORNADA.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    } else {
                      context.push('/add-trip', extra: request);
                    }
                  },
                  child: Text(
                    hasShift ? 'ACEPTAR E INICIAR VIAJE' : 'INICIA JORNADA PARA VER VIAJE',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}

class _DetectedTollPass {
  final String id;
  final PuntoInfraestructuraModel peaje;
  final DateTime passTime;
  final double distanceMeters;
  final bool isFromGps;
  bool isSelected;
  final bool isAlreadySaved;
  final TextEditingController amountController;

  _DetectedTollPass({
    required this.id,
    required this.peaje,
    required this.passTime,
    required this.distanceMeters,
    this.isFromGps = true,
    this.isSelected = true,
    this.isAlreadySaved = false,
    required double initialAmount,
  }) : amountController = TextEditingController(
          text: initialAmount > 0 ? initialAmount.toInt().toString() : '0',
        );

  double get amount => double.tryParse(amountController.text.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;

  void dispose() {
    amountController.dispose();
  }
}

class _EndTripDialog extends ConsumerStatefulWidget {
  final TripModel trip;
  final String targetPlate;

  const _EndTripDialog({
    required this.trip,
    required this.targetPlate,
  });

  @override
  ConsumerState<_EndTripDialog> createState() => _EndTripDialogState();
}

class _EndTripDialogState extends ConsumerState<_EndTripDialog> {
  late final TextEditingController _guideCtrl;
  late final TextEditingController _kmCtrl;
  late final TextEditingController _containerCtrl;
  final _formKey = GlobalKey<FormState>();

  bool _isLoadingGps = true;
  bool _isLoadingTolls = true;
  double? _gpsKm;
  double? _suggestedTheoreticalKm;
  bool _isFinalizing = false;

  List<_DetectedTollPass> _detectedTolls = [];
  List<PuntoInfraestructuraModel> _allAvailablePeajes = [];

  @override
  void initState() {
    super.initState();
    _guideCtrl = TextEditingController(text: widget.trip.guideNumber ?? '');
    _containerCtrl = TextEditingController(text: widget.trip.containerNumber ?? '');
    _kmCtrl = TextEditingController(
      text: (widget.trip.totalKm != null && widget.trip.totalKm! > 0)
          ? widget.trip.totalKm!.toStringAsFixed(1)
          : '',
    );
    _queryGpsAndTolls();
  }

  @override
  void dispose() {
    _guideCtrl.dispose();
    _kmCtrl.dispose();
    _containerCtrl.dispose();
    for (final t in _detectedTolls) {
      t.dispose();
    }
    super.dispose();
  }

  double get _totalValidatedTolls {
    double total = 0.0;
    for (final toll in _detectedTolls) {
      if (toll.isSelected && !toll.isAlreadySaved) {
        total += toll.amount;
      }
    }
    return total;
  }

  Future<void> _queryGpsAndTolls() async {
    if (!mounted) return;
    setState(() {
      _isLoadingGps = true;
      _isLoadingTolls = true;
    });

    try {
      final modoGps = ref.read(modoGpsServiceProvider);
      final activeShift = ref.read(activeShiftProvider).value;
      final endTime = widget.trip.endDate ?? DateTime.now();
      final startTime = widget.trip.startDate;

      // 1. Cargar catálogo universal de peajes
      try {
        final infraRepo = ref.read(infraestructuraRepositoryProvider);
        final puntos = await infraRepo.getPuntos(soloActivos: true);
        _allAvailablePeajes = puntos.where((p) => p.tipo == TipoPuntoInfraestructura.peaje).toList();
      } catch (e) {
        debugPrint('[Peajes] Error cargando catálogo de peajes: $e');
      }

      // 2. Cargar gastos existentes para este viaje (para no duplicar si ya rindió un peaje)
      final existingPeajeNames = <String>[];
      try {
        final existingGastos = await FirebaseFirestore.instance
            .collection('gastos')
            .where('tripId', isEqualTo: widget.trip.id)
            .where('type', isEqualTo: 'Peaje')
            .get();
        for (final doc in existingGastos.docs) {
          final desc = (doc.data()['description'] ?? '').toString().toLowerCase();
          existingPeajeNames.add(desc);
        }
      } catch (e) {
        debugPrint('[Peajes] Error consultando gastos existentes: $e');
      }

      // 3. Consultar intervalo GPS
      final hTrip = await modoGps.fetchTripInterval(
        plate: widget.targetPlate,
        startTime: startTime,
        endTime: endTime,
        idEmpresa: activeShift?.idEmpresa,
      );

      if (hTrip != null && hTrip.totalDistanceKm > 0) {
        _gpsKm = hTrip.totalDistanceKm;
        _kmCtrl.text = _gpsKm!.toStringAsFixed(1);
      } else {
        final distSvc = ref.read(distanceServiceProvider);
        final theoretical = distSvc.lookupKm(widget.trip.client, widget.trip.destination);
        if (theoretical != null) {
          _suggestedTheoreticalKm = theoretical;
          if (_kmCtrl.text.isEmpty) {
            _kmCtrl.text = theoretical.toStringAsFixed(0);
          }
        }
      }

      // 4. Cruzar puntos de ruta GPS con catálogo de peajes
      if (hTrip != null && hTrip.points.isNotEmpty && _allAvailablePeajes.isNotEmpty) {
        const distanceCalc = Distance();
        final detected = <_DetectedTollPass>[];

        // Lista de candidatos potenciales con distancia y punto exacto de cruce
        final candidatePasses = <_DetectedTollPass>[];

        for (final peaje in _allAvailablePeajes) {
          final peajeLatLng = LatLng(peaje.lat, peaje.lng);

          // Radio adaptativo:
          // Peajes Laterales: radio estricto de 18m para no atrapar el camión que viaja por la autopista central
          // Peajes Troncales: radio de 45m para cubrir las pistas de la calzada
          final maxRadius = RoadInfrastructureDetector.getOptimalDetectionRadius(
            tipoCode: peaje.tipo.code,
            subtipo: peaje.subtipo,
            radioConfigurado: peaje.radioMetros,
          );

          DateTime? lastDetectionTime;
          double minDistanceInPass = double.infinity;
          DateTime bestPointTime = peaje.createdAt;

          for (int ptIdx = 0; ptIdx < hTrip.points.length; ptIdx++) {
            final pt = hTrip.points[ptIdx];
            final distM = ptIdx > 0
                ? RoadInfrastructureDetector.calculateDistanceToSegmentMeters(
                    peajeLatLng,
                    hTrip.points[ptIdx - 1].position,
                    pt.position,
                  )
                : distanceCalc.as(LengthUnit.Meter, peajeLatLng, pt.position);

            if (distM <= maxRadius) {
              // Calcular rumbo del camión evitando jitter si el punto anterior está muy cerca (< 15m)
              double? ptBearing;
              for (int back = ptIdx - 1; back >= 0; back--) {
                final prevPt = hTrip.points[back];
                if (RoadInfrastructureDetector.calculateDistanceMeters(prevPt.position, pt.position) >= 15.0) {
                  ptBearing = RoadInfrastructureDetector.calculateBearing(prevPt.position, pt.position);
                  break;
                }
              }
              if (ptBearing == null && ptIdx < hTrip.points.length - 1) {
                for (int fwd = ptIdx + 1; fwd < hTrip.points.length; fwd++) {
                  final nextPt = hTrip.points[fwd];
                  if (RoadInfrastructureDetector.calculateDistanceMeters(pt.position, nextPt.position) >= 15.0) {
                    ptBearing = RoadInfrastructureDetector.calculateBearing(pt.position, nextPt.position);
                    break;
                  }
                }
              }

              // Validar concordancia de sentido (Norte a Sur vs Sur a Norte, etc.)
              if (!RoadInfrastructureDetector.matchesDirection(truckHeading: ptBearing, sentidoPunto: peaje.sentido)) {
                continue;
              }

              if (lastDetectionTime == null || pt.timestamp.difference(lastDetectionTime).inMinutes.abs() > 20) {
                if (lastDetectionTime != null && minDistanceInPass < double.infinity) {
                  final defaultAmount = peaje.tarifaCamionPesado ?? peaje.tarifaCamionSimple ?? 0.0;
                  final isSaved = existingPeajeNames.any((n) => n.contains(peaje.nombre.toLowerCase()));
                  candidatePasses.add(_DetectedTollPass(
                    id: 'pass-${peaje.id}-${bestPointTime.millisecondsSinceEpoch}',
                    peaje: peaje,
                    passTime: bestPointTime,
                    distanceMeters: minDistanceInPass,
                    isAlreadySaved: isSaved,
                    isSelected: !isSaved,
                    initialAmount: defaultAmount,
                  ));
                }
                lastDetectionTime = pt.timestamp;
                minDistanceInPass = distM;
                bestPointTime = pt.timestamp;
              } else {
                if (distM < minDistanceInPass) {
                  minDistanceInPass = distM;
                  bestPointTime = pt.timestamp;
                }
              }
            }
          }

          if (lastDetectionTime != null && minDistanceInPass < double.infinity) {
            final defaultAmount = peaje.tarifaCamionPesado ?? peaje.tarifaCamionSimple ?? 0.0;
            final isSaved = existingPeajeNames.any((n) => n.contains(peaje.nombre.toLowerCase()));
            candidatePasses.add(_DetectedTollPass(
              id: 'pass-${peaje.id}-${bestPointTime.millisecondsSinceEpoch}',
              peaje: peaje,
              passTime: bestPointTime,
              distanceMeters: minDistanceInPass,
              isAlreadySaved: isSaved,
              isSelected: !isSaved,
              initialAmount: defaultAmount,
            ));
          }
        }

        // DESEMPATE DE CASILLAS PARALELAS (Nearest Gate Competition):
        // Si dos casetas de peaje (ej. Cabrero Norte vs Sur, o Puente Industrial) fueron detectadas
        // en una misma ventana de tiempo (< 3 minutos), nos quedamos con la que tuvo menor distancia física
        // al camión (la pista exacta por la que circulaba).
        candidatePasses.sort((a, b) => a.passTime.compareTo(b.passTime));

        for (final cand in candidatePasses) {
          final conflictingIdx = detected.indexWhere((existing) {
            final diffSec = cand.passTime.difference(existing.passTime).inSeconds.abs();
            return diffSec < 180; // Misma ventana de paso
          });

          if (conflictingIdx >= 0) {
            final existing = detected[conflictingIdx];
            // Si el nuevo candidato está físicamente más cerca de la calzada que el anterior, lo reemplaza
            if (cand.distanceMeters < existing.distanceMeters) {
              detected[conflictingIdx] = cand;
            }
          } else {
            detected.add(cand);
          }
        }

        detected.sort((a, b) => a.passTime.compareTo(b.passTime));

        for (final t in _detectedTolls) {
          t.dispose();
        }
        _detectedTolls = detected;
      }
    } catch (e) {
      debugPrint('[FinalizarViaje] Error en telemetría o peajes: $e');
      final distSvc = ref.read(distanceServiceProvider);
      final theoretical = distSvc.lookupKm(widget.trip.client, widget.trip.destination);
      if (theoretical != null && _kmCtrl.text.isEmpty) {
        _suggestedTheoreticalKm = theoretical;
        _kmCtrl.text = theoretical.toStringAsFixed(0);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingGps = false;
          _isLoadingTolls = false;
        });
      }
    }
  }

  void _showAddManualTollDialog() {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    PuntoInfraestructuraModel? selectedFromCatalog;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF1E242B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_road, color: Colors.amberAccent, size: 20),
              SizedBox(width: 8),
              Text('Agregar Peaje al Viaje', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Seleccionar del Catálogo de Peajes:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<PuntoInfraestructuraModel?>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E242B),
                      value: selectedFromCatalog,
                      hint: const Text('Elegir peaje registrado...', style: TextStyle(color: Colors.white60, fontSize: 13)),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Otro (Ingreso manual libre)', style: TextStyle(color: Colors.cyanAccent, fontSize: 13)),
                        ),
                        ..._allAvailablePeajes.map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                '${p.nombre} (${p.ruta})',
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: (val) {
                        setDlgState(() {
                          selectedFromCatalog = val;
                          if (val != null) {
                            nameCtrl.text = val.nombre;
                            final rate = val.tarifaCamionPesado ?? val.tarifaCamionSimple ?? 0.0;
                            if (rate > 0) amountCtrl.text = rate.toInt().toString();
                          }
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Nombre del Peaje',
                    labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Monto a Rendir (\$)',
                    labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(color: Colors.amberAccent),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (name.isEmpty) return;

                final model = selectedFromCatalog ??
                    PuntoInfraestructuraModel(
                      id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
                      nombre: name,
                      tipo: TipoPuntoInfraestructura.peaje,
                      subtipo: 'Manual',
                      ruta: '',
                      lat: 0.0,
                      lng: 0.0,
                      radioMetros: 0,
                      sentido: 'Bidireccional',
                      creadoPor: 'CONDUCTOR',
                      createdAt: DateTime.now(),
                    );

                final newPass = _DetectedTollPass(
                  id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
                  peaje: model,
                  passTime: DateTime.now(),
                  distanceMeters: 0,
                  isFromGps: false,
                  isSelected: true,
                  initialAmount: amount,
                );

                setState(() {
                  _detectedTolls.add(newPass);
                });

                Navigator.pop(ctx);
              },
              child: const Text('AGREGAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTollsSection() {
    final currencyFmt = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.toll_outlined, size: 16, color: Colors.amberAccent),
                const SizedBox(width: 6),
                const Text(
                  'Peajes en Ruta',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                if (_detectedTolls.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_detectedTolls.length}',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            if (_isLoadingTolls)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
              ),
          ],
        ),
        const SizedBox(height: 6),

        if (_isLoadingTolls)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, size: 14, color: Colors.amberAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Identificando pasadas por peajes...',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                  ),
                ),
              ],
            ),
          )
        else if (_detectedTolls.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.toll_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Sin pasadas por peajes detectadas en este tramo.',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ),
                InkWell(
                  onTap: _showAddManualTollDialog,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: Colors.amberAccent),
                        SizedBox(width: 2),
                        Text('Agregar', style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          ..._detectedTolls.map((toll) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: toll.isAlreadySaved
                    ? Colors.white.withValues(alpha: 0.03)
                    : (toll.isSelected ? const Color(0xFF1E2836) : Colors.black12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: toll.isAlreadySaved
                      ? Colors.green.withValues(alpha: 0.3)
                      : (toll.isSelected ? Colors.amber.withValues(alpha: 0.4) : Colors.white10),
                ),
              ),
              child: Row(
                children: [
                  if (toll.isAlreadySaved)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.check_circle, size: 18, color: Colors.greenAccent),
                    )
                  else
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Checkbox(
                        value: toll.isSelected,
                        activeColor: Colors.amberAccent,
                        checkColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        visualDensity: VisualDensity.compact,
                        onChanged: (val) {
                          setState(() {
                            toll.isSelected = val ?? false;
                          });
                        },
                      ),
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                toll.peaje.nombre,
                                style: TextStyle(
                                  color: toll.isSelected ? Colors.white : Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  decoration: toll.isSelected ? null : TextDecoration.lineThrough,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (toll.isAlreadySaved)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('Rendido', style: TextStyle(color: Colors.greenAccent, fontSize: 9.5, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          toll.isFromGps
                              ? '${toll.peaje.ruta.isNotEmpty ? "${toll.peaje.ruta} • " : ""}🛰️ ${DateFormat('HH:mm').format(toll.passTime)} hrs (~${toll.distanceMeters.toStringAsFixed(0)}m)'
                              : '${toll.peaje.ruta.isNotEmpty ? "${toll.peaje.ruta} • " : ""}✍️ Agregado manual',
                          style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 82,
                    child: TextFormField(
                      controller: toll.amountController,
                      enabled: toll.isSelected && !toll.isAlreadySaved,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: toll.isSelected ? Colors.amberAccent : Colors.grey,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText: '\$ ',
                        prefixStyle: const TextStyle(color: Colors.white70, fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        filled: true,
                        fillColor: Colors.black38,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.amberAccent)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (!toll.isFromGps && !toll.isAlreadySaved)
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                      padding: const EdgeInsets.only(left: 4),
                      constraints: const BoxConstraints(),
                      tooltip: 'Quitar',
                      onPressed: () {
                        setState(() {
                          toll.dispose();
                          _detectedTolls.remove(toll);
                        });
                      },
                    ),
                ],
              ),
            );
          }),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: _showAddManualTollDialog,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline, size: 14, color: Colors.amberAccent),
                      SizedBox(width: 4),
                      Text('Agregar otro peaje', style: TextStyle(color: Colors.amberAccent, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              Text(
                'Total: ${currencyFmt.format(_totalValidatedTolls)}',
                style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('HH:mm');
    final startTimeStr = timeFmt.format(widget.trip.startDate);
    final endTimeStr = timeFmt.format(DateTime.now());

    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 22),
          ),
          const SizedBox(width: 12),
          const Text('Finalizar Viaje', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.route, size: 14, color: Colors.white60),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${widget.trip.origin} ➔ ${widget.trip.destination}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Banner de recomendación GPS
              if (_isLoadingGps)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Consultando KM reales y peajes capturados por GPS...',
                          style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_gpsKm != null && _gpsKm! > 0)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F5132).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.satellite_alt, color: Colors.greenAccent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🛰️ GPS Detectó: ${_gpsKm!.toStringAsFixed(1)} KM reales',
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Tramo: $startTimeStr ➔ $endTimeStr (${widget.targetPlate})',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18, color: Colors.greenAccent),
                        tooltip: 'Recalcular GPS',
                        onPressed: _queryGpsAndTolls,
                      ),
                    ],
                  ),
                )
              else if (_suggestedTheoreticalKm != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'KM sugerido por tabla: ${_suggestedTheoreticalKm!.toStringAsFixed(0)} KM',
                          style: const TextStyle(color: Colors.purpleAccent, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Sin señal GPS en este tramo. Ingrese los KM manualmente.',
                          style: TextStyle(color: Colors.amber, fontSize: 11),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 16, color: Colors.amber),
                        onPressed: _queryGpsAndTolls,
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 14),

              // SECCIÓN DE PEAJES DETECTADOS / VALIDACIÓN
              _buildTollsSection(),

              const SizedBox(height: 16),
              // Si el viaje no tiene contenedor (o es retiro anticipado), permitir ingresarlo aquí
              if (widget.trip.containerNumber == null || widget.trip.containerNumber!.isEmpty || widget.trip.tipoMovimiento == 'retiro_anticipado') ...[
                TextFormField(
                  controller: _containerCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Nº Contenedor Asignado (opcional)',
                    labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 13),
                    hintText: 'Ej: MSMU3836691',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.inventory_2_outlined, color: Colors.cyanAccent, size: 20),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _guideCtrl,
                keyboardType: TextInputType.text,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nº Guía de Despacho (opcional)',
                  labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  hintText: 'Ej: 12345',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _kmCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Kilómetros recorridos',
                  labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  suffixText: 'KM',
                  suffixStyle: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: _gpsKm != null ? Colors.green.withValues(alpha: 0.1) : Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: _gpsKm != null ? const BorderSide(color: Colors.greenAccent, width: 1) : BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: _gpsKm != null ? const BorderSide(color: Colors.greenAccent, width: 1) : BorderSide.none,
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa los kilómetros recorridos';
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
      ),
      actions: [
        TextButton(
          onPressed: _isFinalizing ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFFFFF),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isFinalizing
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(context);

                  setState(() => _isFinalizing = true);

                  final parsedKm = double.tryParse(_kmCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
                  final activeShift = ref.read(activeShiftProvider).value;

                  try {
                    // 1. Finalizar viaje y registrar odómetro / guía
                    await ref.read(tripRepositoryProvider).endTripWithGuide(
                      widget.trip.id,
                      _guideCtrl.text.trim(),
                      totalKm: parsedKm,
                      containerNumber: _containerCtrl.text.trim().isNotEmpty ? _containerCtrl.text.trim().toUpperCase() : null,
                    );

                    // 2. Guardar y conciliar los peajes seleccionados en /gastos
                    int savedTollsCount = 0;
                    double totalTollsAmount = 0.0;

                    for (final toll in _detectedTolls) {
                      if (!toll.isSelected || toll.isAlreadySaved) continue;
                      final tollAmount = toll.amount;
                      if (tollAmount <= 0) continue;

                      final bucket10m = toll.passTime.millisecondsSinceEpoch ~/ 600000;
                      final expenseId = 'EXP-TOLL-${widget.trip.id}-${toll.peaje.id}-$bucket10m';
                      final expense = ExpenseModel(
                        id: expenseId,
                        idEmpresa: activeShift?.idEmpresa ?? widget.trip.idEmpresa,
                        idChofer: widget.trip.idChofer,
                        idJornada: widget.trip.idJornada,
                        tripId: widget.trip.id,
                        amount: tollAmount,
                        type: 'Peaje',
                        litros: null,
                        date: toll.passTime,
                        description: 'Peaje: ${toll.peaje.nombre}${toll.peaje.ruta.isNotEmpty ? ' (${toll.peaje.ruta})' : ''}',
                        status: 'Pendiente',
                        vehicleId: widget.trip.vehicleId ?? widget.targetPlate,
                      );

                      await ref.read(tripRepositoryProvider).addExpense(expense);
                      savedTollsCount++;
                      totalTollsAmount += tollAmount;
                    }

                    nav.pop();

                    final currencyFmt = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);
                    final tollsMsg = savedTollsCount > 0
                        ? ' • $savedTollsCount peajes conciliados (${currencyFmt.format(totalTollsAmount)})'
                        : '';

                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('✓ Viaje cerrado: ${parsedKm.toStringAsFixed(1)} KM$tollsMsg'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      setState(() => _isFinalizing = false);
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error al finalizar viaje: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
          child: _isFinalizing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('FINALIZAR', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ================= DIÁLOGO DE CIERRE Y CONCILIACIÓN DE JORNADA =================

class _EndShiftDialog extends ConsumerStatefulWidget {
  final ShiftModel shift;
  final List<TripModel> completedTrips;

  const _EndShiftDialog({
    required this.shift,
    required this.completedTrips,
  });

  @override
  ConsumerState<_EndShiftDialog> createState() => _EndShiftDialogState();
}

class _EndShiftDialogState extends ConsumerState<_EndShiftDialog> {
  final _ctrl = TextEditingController();
  bool _isLoadingGps = true;
  double? _gpsTotalKm;
  String _unregisteredReason = 'Retorno a Base vacío';
  bool _isSubmitting = false;

  final List<String> _reasonOptions = [
    'Retorno a Base vacío',
    'Traslado a Taller / Mantención',
    'Carga de Combustible / Servicios',
    'Movimiento Operacional en Patio',
    'Otro movimiento autorizado',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    _fetchGpsDistance();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _fetchGpsDistance() async {
    try {
      final modoGps = ref.read(modoGpsServiceProvider);
      final dist = await modoGps.getGpsDistanceForInterval(
        plate: widget.shift.patenteCamion,
        startTime: widget.shift.startTime,
        endTime: DateTime.now(),
        idEmpresa: widget.shift.idEmpresa,
      );
      if (mounted) {
        setState(() {
          _gpsTotalKm = dist;
          _isLoadingGps = false;
          // Si el chofer aún no ha tipeado y el GPS arrojó distancia positiva, sugerir el odómetro calculado
          if (_ctrl.text.isEmpty && dist != null && dist > 0) {
            final suggested = widget.shift.startOdometer + dist.round();
            _ctrl.text = suggested.toString();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingGps = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripsKm = widget.completedTrips.fold(0.0, (acc, t) => acc + (t.totalKm ?? 0.0));
    final enteredOdo = int.tryParse(_ctrl.text.trim());
    final bool hasValidOdo = enteredOdo != null && enteredOdo >= widget.shift.startOdometer;
    
    final int deltaOdo = hasValidOdo ? (enteredOdo - widget.shift.startOdometer) : 0;
    final double unregisteredKm = (hasValidOdo && deltaOdo > tripsKm) ? (deltaOdo - tripsKm) : 0.0;
    
    double? variationPercent;
    if (hasValidOdo && deltaOdo > 0 && _gpsTotalKm != null && _gpsTotalKm! > 0) {
      variationPercent = ((deltaOdo - _gpsTotalKm!).abs() / deltaOdo) * 100.0;
    }

    final numberFormat = NumberFormat('#,###');

    return AlertDialog(
      backgroundColor: const Color(0xFF16181F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white12)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag_circle, color: Colors.redAccent, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cierre de Jornada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                    Text('Conciliación de Kilometraje y Odómetro', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Camión: ${widget.shift.patenteCamion}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
                Text('Inicio: ${DateFormat('HH:mm').format(widget.shift.startTime)} hrs', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Odómetro Inicial (Verificado)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E222B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.lightBlueAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Odómetro Inicial (Verificado al inicio)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          Text(
                            '${numberFormat.format(widget.shift.startOdometer)} KM',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Input Odómetro Final
              TextFormField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Odómetro Final (Verificar con Tablero)',
                  hintText: 'Ingresa el kilometraje actual',
                  helperText: _isLoadingGps
                      ? 'Consultando telemetría GPS...'
                      : (_gpsTotalKm != null ? 'GPS estimó aprox. ${numberFormat.format(widget.shift.startOdometer + _gpsTotalKm!.round())} KM' : null),
                  helperStyle: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFF222632),
                  prefixIcon: const Icon(Icons.pin_outlined, color: Colors.white70),
                  suffixText: 'KM',
                  suffixStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blueAccent, width: 2)),
                ),
              ),
              const SizedBox(height: 16),

              // 3. Panel de Conciliación
              if (hasValidOdo) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E222B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      _buildMetricRow('Rodaje Total Tablero (Δ):', '${numberFormat.format(deltaOdo)} KM', isBold: true),
                      const Divider(color: Colors.white10, height: 16),
                      _buildMetricRow('Viajes Registrados (GPS):', '${tripsKm.toStringAsFixed(1)} KM (${widget.completedTrips.length} viajes)', color: Colors.greenAccent),
                      const Divider(color: Colors.white10, height: 16),
                      _buildMetricRow('Distancia Total Satelital:', _isLoadingGps ? 'Calculando...' : '${_gpsTotalKm?.toStringAsFixed(1) ?? '--'} KM', color: Colors.cyanAccent),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Alerta de Kilómetros No Registrados (Km Muertos)
                if (unregisteredKm > 2.0) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.alt_route, color: Colors.amberAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '+${unregisteredKm.toStringAsFixed(1)} KM no registrados en viajes',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Diferencia entre el rodaje de tablero y los viajes formalizados. Se justificará como:',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _unregisteredReason,
                          dropdownColor: const Color(0xFF1E222B),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            filled: true,
                            fillColor: const Color(0xFF14171F),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: _reasonOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _unregisteredReason = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 5. Badge de % de Variación Tablero vs GPS
                if (variationPercent != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: variationPercent <= 3.0
                          ? Colors.green.withValues(alpha: 0.15)
                          : (variationPercent <= 8.0
                              ? Colors.amber.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.18)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: variationPercent <= 3.0
                            ? Colors.greenAccent.withValues(alpha: 0.5)
                            : (variationPercent <= 8.0
                                ? Colors.amberAccent.withValues(alpha: 0.5)
                                : Colors.redAccent.withValues(alpha: 0.6)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          variationPercent <= 3.0
                              ? Icons.verified
                              : (variationPercent <= 8.0 ? Icons.info_outline : Icons.warning_amber),
                          color: variationPercent <= 3.0
                              ? Colors.greenAccent
                              : (variationPercent <= 8.0 ? Colors.amberAccent : Colors.redAccent),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            variationPercent <= 3.0
                                ? 'Variación ${variationPercent.toStringAsFixed(1)}% • Tablero y GPS se condicen perfectamente'
                                : (variationPercent <= 8.0
                                    ? 'Variación ${variationPercent.toStringAsFixed(1)}% • Tolerancia normal de rodado'
                                    : 'Variación alta (${variationPercent.toStringAsFixed(1)}%) • Revisa si el odómetro final coincide con el camión'),
                            style: TextStyle(
                              color: variationPercent <= 3.0
                                  ? Colors.greenAccent
                                  : (variationPercent <= 8.0 ? Colors.amberAccent : Colors.redAccent),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else if (_ctrl.text.isNotEmpty && (enteredOdo == null || enteredOdo < widget.shift.startOdometer)) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El odómetro final debe ser mayor o igual al inicial (${numberFormat.format(widget.shift.startOdometer)} KM)',
                          style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: (!hasValidOdo || _isSubmitting)
              ? null
              : () async {
                  setState(() => _isSubmitting = true);
                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(context);
                  try {
                    await ref.read(tripRepositoryProvider).endShift(
                      widget.shift.id,
                      enteredOdo,
                      tripsKm: tripsKm,
                      totalGpsKm: _gpsTotalKm,
                      unregisteredKm: unregisteredKm > 0 ? unregisteredKm : 0.0,
                      unregisteredReason: unregisteredKm > 2.0 ? _unregisteredReason : null,
                      odometerVariationPercent: variationPercent,
                    );
                    if (mounted) {
                      nav.pop();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('✓ Jornada cerrada y kilometraje conciliado exitosamente.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _isSubmitting = false);
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error al cerrar jornada: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
          child: _isSubmitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('CONFIRMAR Y FINALIZAR JORNADA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 14 : 12,
          ),
        ),
      ],
    );
  }
}
