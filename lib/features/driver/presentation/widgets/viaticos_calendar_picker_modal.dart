import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../trips/domain/models/viatico_model.dart';

/// Modal interactivo de calendario mensual con guía cromática para viáticos:
/// 🟢 Verde Esmeralda: Días ya Cobrados y Pagados.
/// 🟡 Ámbar: Días con Rendición Pendiente de Aprobación.
/// 🔵 Azul / Ámbar Brillante: Rango en selección actual.
/// ⚪ Días libres / disponibles para selección.
class ViaticosCalendarPickerModal extends StatefulWidget {
  final List<ViaticoModel> existingViaticos;
  final DateTimeRange? initialRange;

  const ViaticosCalendarPickerModal({
    super.key,
    required this.existingViaticos,
    this.initialRange,
  });

  static Future<DateTimeRange?> show({
    required BuildContext context,
    required List<ViaticoModel> existingViaticos,
    DateTimeRange? initialRange,
  }) {
    return showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ViaticosCalendarPickerModal(
        existingViaticos: existingViaticos,
        initialRange: initialRange,
      ),
    );
  }

  @override
  State<ViaticosCalendarPickerModal> createState() => _ViaticosCalendarPickerModalState();
}

class _ViaticosCalendarPickerModalState extends State<ViaticosCalendarPickerModal> {
  late DateTime _currentMonth;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  String? _selectionWarning;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    if (widget.initialRange != null) {
      _rangeStart = DateUtils.dateOnly(widget.initialRange!.start);
      _rangeEnd = DateUtils.dateOnly(widget.initialRange!.end);
    }
  }

  ViaticoModel? _findViaticoForDay(DateTime day) {
    final d = DateUtils.dateOnly(day);
    for (final v in widget.existingViaticos) {
      final s = DateUtils.dateOnly(v.fechaInicio);
      final e = DateUtils.dateOnly(v.fechaFin);
      if (!d.isBefore(s) && !d.isAfter(e)) {
        return v;
      }
    }
    return null;
  }


  void _onDayTapped(DateTime day) {
    final d = DateUtils.dateOnly(day);
    final today = DateUtils.dateOnly(DateTime.now());

    if (d.isAfter(today)) {
      setState(() {
        _selectionWarning = 'No puedes seleccionar fechas futuras.';
      });
      return;
    }

    final viatico = _findViaticoForDay(d);
    if (viatico != null) {
      setState(() {
        final estado = viatico.isPagado ? 'PAGADO' : 'PENDIENTE DE PAGO';
        _selectionWarning = 'El día ${DateFormat('dd/MM/yyyy').format(d)} ya está $estado.';
      });
      return;
    }

    setState(() {
      _selectionWarning = null;

      // Si no hay rango iniciado o ya teníamos un rango completo, empezamos uno nuevo
      if (_rangeStart == null || (_rangeStart != null && _rangeEnd != null)) {
        _rangeStart = d;
        _rangeEnd = null;
      } else {
        // Teníamos solo inicio, ahora seleccionamos el fin
        DateTime start = _rangeStart!;
        DateTime end = d;

        if (end.isBefore(start)) {
          final temp = start;
          start = end;
          end = temp;
        }

        // Validar que en medio del rango no haya días ya cobrados o pendientes
        bool hasConflict = false;
        DateTime cur = start;
        while (!cur.isAfter(end)) {
          final conflict = _findViaticoForDay(cur);
          if (conflict != null) {
            hasConflict = true;
            break;
          }
          cur = cur.add(const Duration(days: 1));
        }

        if (hasConflict) {
          _selectionWarning = 'El rango contiene días ya cobrados o en proceso de aprobación.';
          _rangeStart = d;
          _rangeEnd = null;
        } else {
          _rangeStart = start;
          _rangeEnd = end;
        }
      }
    });
  }

  void _confirmSelection() {
    if (_rangeStart == null) return;
    final end = _rangeEnd ?? _rangeStart!;
    Navigator.of(context).pop(DateTimeRange(start: _rangeStart!, end: end));
  }

  @override
  Widget build(BuildContext context) {
    final monthName = DateFormat('MMMM yyyy', 'es_CL').format(_currentMonth);
    final daysInMonth = DateUtils.getDaysInMonth(_currentMonth.year, _currentMonth.month);
    final firstDayOffset = (DateTime(_currentMonth.year, _currentMonth.month, 1).weekday - 1); // 0 = Lunes

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Píldora superior de arrastre
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Cabecera: Título y Navegación de mes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Guía Visual de Viáticos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      monthName[0].toUpperCase() + monthName.substring(1),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                      onPressed: () {
                        final next = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
                        final now = DateTime.now();
                        if (!next.isAfter(DateTime(now.year, now.month + 1, 1))) {
                          setState(() => _currentMonth = next);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Leyenda explicativa en badges
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF161A22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _LegendIndicator(
                    color: AppColors.success,
                    label: 'Pagado',
                  ),
                  _LegendIndicator(
                    color: AppColors.primary,
                    label: 'Pendiente',
                  ),
                  _LegendIndicator(
                    color: Color(0xFF38BDF8),
                    label: 'Seleccionado',
                  ),
                  _LegendIndicator(
                    color: Color(0xFF64748B),
                    label: 'Disponible',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Encabezado de Días de la semana (Lun, Mar, Mié...)
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _WeekDayLabel('L'),
                _WeekDayLabel('M'),
                _WeekDayLabel('M'),
                _WeekDayLabel('J'),
                _WeekDayLabel('V'),
                _WeekDayLabel('S'),
                _WeekDayLabel('D'),
              ],
            ),
            const SizedBox(height: 8),

            // Matriz de Días del Mes
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: firstDayOffset + daysInMonth,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.15,
              ),
              itemBuilder: (context, index) {
                if (index < firstDayOffset) {
                  return const SizedBox.shrink();
                }
                final dayNumber = index - firstDayOffset + 1;
                final dayDate = DateTime(_currentMonth.year, _currentMonth.month, dayNumber);
                final viatico = _findViaticoForDay(dayDate);
                final today = DateUtils.dateOnly(DateTime.now());
                final isFuture = dayDate.isAfter(today);

                final isStart = _rangeStart != null && DateUtils.isSameDay(dayDate, _rangeStart);
                final isEnd = _rangeEnd != null && DateUtils.isSameDay(dayDate, _rangeEnd);
                final inSelectedRange = _rangeStart != null &&
                    _rangeEnd != null &&
                    !dayDate.isBefore(_rangeStart!) &&
                    !dayDate.isAfter(_rangeEnd!);

                Color bgColor = Colors.transparent;
                Color textColor = AppColors.textPrimary;
                Border? border;

                if (viatico != null) {
                  if (viatico.isPagado) {
                    bgColor = AppColors.success.withValues(alpha: 0.18);
                    border = Border.all(color: AppColors.success, width: 1.2);
                    textColor = AppColors.success;
                  } else {
                    bgColor = AppColors.primary.withValues(alpha: 0.18);
                    border = Border.all(color: AppColors.primary, width: 1.2);
                    textColor = AppColors.primary;
                  }
                } else if (isStart || isEnd || inSelectedRange) {
                  bgColor = const Color(0xFF38BDF8).withValues(alpha: 0.35);
                  border = Border.all(color: const Color(0xFF38BDF8), width: 1.5);
                  textColor = Colors.white;
                } else if (isFuture) {
                  textColor = Colors.white24;
                } else {
                  bgColor = const Color(0xFF161A22);
                  border = Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.8);
                }

                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _onDayTapped(dayDate),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: border,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$dayNumber',
                      style: TextStyle(
                        fontWeight: (isStart || isEnd || viatico != null) ? FontWeight.bold : FontWeight.w500,
                        color: textColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),

            if (_selectionWarning != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.4), width: 0.8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectionWarning!,
                        style: const TextStyle(color: AppColors.error, fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Resumen de Selección y Botón de Confirmación
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Rango Elegido:', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      const SizedBox(height: 2),
                      Text(
                        _rangeStart == null
                            ? 'Ninguno'
                            : (_rangeEnd == null
                                ? DateFormat('dd/MM/yyyy').format(_rangeStart!)
                                : '${DateFormat('dd/MM').format(_rangeStart!)} al ${DateFormat('dd/MM/yy').format(_rangeEnd!)}'),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rangeStart != null ? AppColors.primary : Colors.white12,
                    foregroundColor: _rangeStart != null ? AppColors.background : Colors.white30,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _rangeStart == null ? null : _confirmSelection,
                  child: const Text('CONFIRMAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekDayLabel extends StatelessWidget {
  final String label;
  const _WeekDayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _LegendIndicator extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendIndicator({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

