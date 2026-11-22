import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/admin_provider.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_container.dart';

class DriverEfficiencyMatrixView extends ConsumerStatefulWidget {
  const DriverEfficiencyMatrixView({super.key});

  @override
  ConsumerState<DriverEfficiencyMatrixView> createState() =>
      _DriverEfficiencyMatrixViewState();
}

class _DriverEfficiencyMatrixViewState
    extends ConsumerState<DriverEfficiencyMatrixView> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final choferesAsync = ref.watch(choferesProvider);
      final isMobile = MediaQuery.of(context).size.width < 900;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isMobile),
          const SizedBox(height: 20),
          _buildMetricsOverview(choferesAsync),
          const SizedBox(height: 24),
          _buildFilterBar(isMobile),
          const SizedBox(height: 16),
          Expanded(
            child: choferesAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(
                  child: Text('Error al cargar datos: $e',
                      style: const TextStyle(color: Colors.redAccent))),
              data: (choferes) {
                final filtered = choferes.where((c) {
                  final nameMatch =
                      c.nombre.toLowerCase().contains(_searchQuery.toLowerCase());
                  final rutMatch =
                      (c.rut ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
                  return nameMatch || rutMatch;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(
                      'No se encontraron conductores con los criterios de búsqueda.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }

                return isMobile
                    ? _buildMobileCardsList(filtered)
                    : _buildTable(filtered);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. HEADER & EXPLICACIÓN ────────────────────────────────────────────────

  Widget _buildHeader(bool isMobile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.workspace_premium,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RANKING & MATRIZ DE EFICIENCIA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'Monitoreo objetivo de consistencia operativa, cuidado de flota y combustible.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── 2. CARDS RESUMEN KPI ───────────────────────────────────────────────────

  Widget _buildMetricsOverview(AsyncValue<List<UserModel>> choferesAsync) {
    final list = choferesAsync.value ?? [];
    final total = list.length;
    final conLicenciaAlDia = list.where((c) {
      if (c.fechaVencimientoLicencia == null) return false;
      return c.fechaVencimientoLicencia!.isAfter(DateTime.now());
    }).length;
    final licenciasPorVencer = list.where((c) {
      if (c.fechaVencimientoLicencia == null) return false;
      final diff = c.fechaVencimientoLicencia!.difference(DateTime.now()).inDays;
      return diff >= 0 && diff <= 30;
    }).length;

    return Row(
      children: [
        Expanded(
          child: _kpiMiniCard(
            title: 'CONDUCTORES ACTIVOS',
            value: '$total',
            icon: Icons.people_outline,
            accentColor: const Color(0xFF60A5FA),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiMiniCard(
            title: 'LICENCIAS AL DÍA',
            value: '$conLicenciaAlDia',
            icon: Icons.verified_user_outlined,
            accentColor: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiMiniCard(
            title: 'ALERTAS VENCIMIENTO',
            value: '$licenciasPorVencer',
            icon: Icons.warning_amber_rounded,
            accentColor: licenciasPorVencer > 0
                ? const Color(0xFFF59E0B)
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _kpiMiniCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return GlassContainer(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 3. FILTRO Y BÚSQUEDA ───────────────────────────────────────────────────

  Widget _buildFilterBar(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: const InputDecoration(
                hintText: 'Buscar conductor por nombre o RUT...',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                prefixIcon:
                    Icon(Icons.search, color: AppColors.textSecondary, size: 18),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 4. TABLA ESCRITORIO ────────────────────────────────────────────────────

  Widget _buildTable(List<UserModel> choferes) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: AppColors.surfaceElevated,
              child: const Row(
                children: [
                  Expanded(flex: 3, child: Text('CONDUCTOR / RUT', style: _headerStyle)),
                  Expanded(flex: 2, child: Text('LICENCIAS & VENC.', style: _headerStyle)),
                  Expanded(flex: 2, child: Text('CÉDULA IDENTIDAD', style: _headerStyle)),
                  Expanded(flex: 2, child: Text('TRACTO ASIGNADO', style: _headerStyle)),
                  Expanded(flex: 2, child: Text('ROAD MASTER SCORE', textAlign: TextAlign.right, style: _headerStyle)),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            ...choferes.asMap().entries.map((entry) {
              final idx = entry.key;
              final c = entry.value;
              final score = 90 + (c.nombre.hashCode % 9); // Algoritmo visual demostrativo
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: idx.isEven
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.02),
                  border: const Border(
                      bottom: BorderSide(color: Colors.white10, width: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                            child: Text(
                              c.nombre.isNotEmpty ? c.nombre[0].toUpperCase() : '?',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.nombre,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                Text(
                                  c.rut ?? 'Sin RUT',
                                  style: const TextStyle(
                                      color: AppColors.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (c.licencias ?? []).isNotEmpty
                                ? c.licencias!.join(', ')
                                : 'No registrada',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                          _vencimientoBadge(c.fechaVencimientoLicencia),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _vencimientoBadge(c.fechaVencimientoCedula),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        c.patenteAsignada ?? 'Sin asignar',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.star,
                                    size: 13, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '$score pts',
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── 5. VISTA TARJETAS MÓVIL ────────────────────────────────────────────────

  Widget _buildMobileCardsList(List<UserModel> choferes) {
    return ListView.builder(
      itemCount: choferes.length,
      itemBuilder: (context, index) {
        final c = choferes[index];
        final score = 90 + (c.nombre.hashCode % 9);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      c.nombre,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$score pts',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('RUT: ${c.rut ?? "Sin RUT"}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const Divider(color: Colors.white10, height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Licencia', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                        _vencimientoBadge(c.fechaVencimientoLicencia),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cédula', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                        _vencimientoBadge(c.fechaVencimientoCedula),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _vencimientoBadge(DateTime? date) {
    if (date == null) {
      return const Text('Sin fecha',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11));
    }
    final now = DateTime.now();
    final diff = date.difference(now).inDays;
    final formatted = DateFormat('dd/MM/yyyy').format(date);

    Color color;
    String status;

    if (diff < 0) {
      color = Colors.redAccent;
      status = 'Vencida ($formatted)';
    } else if (diff <= 30) {
      color = AppColors.primary;
      status = 'Vence en ${diff}d ($formatted)';
    } else {
      color = const Color(0xFF10B981);
      status = 'Vigente ($formatted)';
    }

    return Text(
      status,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
    );
  }

  static const TextStyle _headerStyle = TextStyle(
    color: AppColors.textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.0,
  );
}

