import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../domain/models/incidencia_model.dart';
import '../../../trips/domain/models/vehicle_model.dart';
import '../providers/admin_provider.dart';
import '../../../../core/utils/chilean_holidays.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Diálogo para registrar una nueva incidencia / ingreso a taller por parte del Administrador o Encargado.
void showCreateIncidenciaDialog(BuildContext context, WidgetRef ref, List<VehicleModel> vehicles) {
  final descCtrl = TextEditingController();
  final tallerCtrl = TextEditingController();
  final facturaCtrl = TextEditingController();
  final costoCtrl = TextEditingController();

  String tipo = 'Mecánica';
  String estado = 'En Taller';
  String? selectedVehicleId = vehicles.isNotEmpty ? vehicles.first.id : null;
  DateTime fechaIngreso = DateTime.now();
  DateTime? fechaSalida;

  if (vehicles.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay vehículos registrados para reportar incidencia.')),
    );
    return;
  }

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final veh = vehicles.firstWhere(
          (v) => v.id == selectedVehicleId,
          orElse: () => vehicles.first,
        );

        final diasCalculados = ChileanHolidays.getDiasDetenidosHabiles(fechaIngreso, fechaSalida);

        return Dialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 500,
            constraints: const BoxConstraints(maxHeight: 750),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Ingresar Mantención / Taller',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Selector de Vehículo
                  DropdownButtonFormField<String>(
                    initialValue: selectedVehicleId,
                    dropdownColor: const Color(0xFF242424),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Camión / Patente',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.black26,
                    ),
                    items: vehicles
                        .map((v) => DropdownMenuItem(value: v.id, child: Text('${v.patente} (${v.marca ?? "Camión"})')))
                        .toList(),
                    onChanged: (val) => setDialogState(() => selectedVehicleId = val),
                  ),
                  const SizedBox(height: 12),

                  // Tipo de Falla
                  DropdownButtonFormField<String>(
                    initialValue: tipo,
                    dropdownColor: const Color(0xFF242424),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Mantención',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.black26,
                    ),
                    items: ['Mecánica', 'Neumáticos', 'Preventivo', 'Eléctrica', 'Carrocería', 'Documentos', 'Otros']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => tipo = val!),
                  ),
                  const SizedBox(height: 12),

                  // Estado Inicial
                  DropdownButtonFormField<String>(
                    initialValue: estado,
                    dropdownColor: const Color(0xFF242424),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Estado Actual',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.black26,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'En Taller', child: Text('En Taller (Detenido)')),
                      DropdownMenuItem(value: 'Pendiente', child: Text('Pendiente de Ingreso')),
                      DropdownMenuItem(value: 'Solucionado', child: Text('Solucionado (Ya Entregado)')),
                    ],
                    onChanged: (val) => setDialogState(() {
                      estado = val!;
                      if (estado == 'Solucionado' && fechaSalida == null) {
                        fechaSalida = DateTime.now();
                      }
                    }),
                  ),
                  const SizedBox(height: 16),

                  // Fechas de Taller
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: fechaIngreso,
                              firstDate: DateTime(2023),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) setDialogState(() => fechaIngreso = d);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Ingreso a Taller', style: TextStyle(color: Colors.grey, fontSize: 10)),
                                const SizedBox(height: 4),
                                Text(DateFormat('dd/MM/yyyy').format(fechaIngreso),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: fechaSalida ?? fechaIngreso,
                              firstDate: fechaIngreso,
                              lastDate: DateTime(2030),
                            );
                            if (d != null) {
                              setDialogState(() {
                                fechaSalida = d;
                                estado = 'Solucionado';
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Salida de Taller (Opcional)', style: TextStyle(color: Colors.grey, fontSize: 10)),
                                const SizedBox(height: 4),
                                Text(
                                  fechaSalida != null ? DateFormat('dd/MM/yyyy').format(fechaSalida!) : 'Aún en taller',
                                  style: TextStyle(
                                    color: fechaSalida != null ? Colors.greenAccent : Colors.orangeAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Pill de Días Detenidos calculados con Lunes a Sábado sin feriados
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.orangeAccent, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Días detenidos calculados: $diasCalculados hábiles (Lun-Sáb, sin feriados)',
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Descripción del trabajo o falla',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.black26,
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: tallerCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Taller / Proveedor (Ej: Taller Central, Copec)',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.black26,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: costoCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Costo (\$)',
                            labelStyle: TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: Colors.black26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: facturaCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Nº Factura',
                            labelStyle: TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: Colors.black26,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onPressed: () async {
                          final user = ref.read(currentUserProfileProvider).value;
                          final cleanCost = costoCtrl.text.replaceAll('.', '').replaceAll(',', '.').trim();
                          final costo = cleanCost.isNotEmpty ? double.tryParse(cleanCost) : null;

                          final incidencia = IncidenciaModel(
                            id: '',
                            idEmpresa: user?.idEmpresa ?? '',
                            vehicleId: veh.id,
                            vehiclePatente: veh.patente,
                            idChofer: user?.uid ?? 'ADMIN',
                            choferNombre: user?.nombre ?? 'Administrador',
                            tipo: tipo,
                            descripcion: descCtrl.text.isEmpty ? 'Mantención en taller' : descCtrl.text,
                            fecha: fechaIngreso,
                            fechaIngresoTaller: fechaIngreso,
                            fechaResolucion: fechaSalida,
                            estado: estado,
                            costoReparacion: costo,
                            tallerProveedor: tallerCtrl.text.isNotEmpty ? tallerCtrl.text : null,
                            numeroFactura: facturaCtrl.text.isNotEmpty ? facturaCtrl.text : null,
                          );

                          // Si tiene costo y está solucionado, convertimos a gasto automáticamente
                          if (costo != null && costo > 0 && estado == 'Solucionado') {
                            await ref.read(adminRepositoryProvider).saveIncidencia(incidencia);
                            await ref.read(adminRepositoryProvider).convertIncidenciaToExpense(
                                  incidencia,
                                  costo,
                                  fechaResolucion: fechaSalida,
                                  fechaIngresoTaller: fechaIngreso,
                                  tallerProveedor: tallerCtrl.text,
                                  numeroFactura: facturaCtrl.text,
                                );
                          } else {
                            await ref.read(adminRepositoryProvider).saveIncidencia(incidencia);
                          }

                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Incidencia y mantención guardada exitosamente'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                        child: const Text('Guardar Registro', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
