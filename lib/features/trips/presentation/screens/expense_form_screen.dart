import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bitacora/features/trips/presentation/providers/trip_provider.dart';
import 'package:bitacora/features/trips/domain/models/expense_model.dart';
import 'package:bitacora/features/auth/presentation/providers/auth_provider.dart';
import 'package:bitacora/features/admin/presentation/providers/admin_provider.dart';
import 'package:bitacora/core/utils/number_utils.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  final String? initialType;
  const ExpenseFormScreen({super.key, this.initialType});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _litrosController = TextEditingController();
  final _odometerController = TextEditingController();
  final _horometroController = TextEditingController();
  final _onboardComputerController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedType = 'Peaje';
  String _destinoCombustible = 'CAMION'; // 'CAMION' | 'AUXILIAR'
  bool _isFullTank = false; // Evento de calibración / llenado a tope
  bool _isExento = true; // Por defecto Peaje es exento

  final List<String> _expenseTypes = ['Peaje', 'Combustible', 'Mantenimiento / Taller', 'Repuesto / Insumo', 'Otros'];

  bool get _isCombustible => _selectedType == 'Combustible';

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null && _expenseTypes.contains(widget.initialType)) {
      _selectedType = widget.initialType!;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _litrosController.dispose();
    _odometerController.dispose();
    _horometroController.dispose();
    _onboardComputerController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      final user = ref.read(currentUserProfileProvider).value;
      final shift = ref.read(activeShiftProvider).value;

      if (user == null || shift == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: No hay jornada activa para asociar este gasto.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final amountValue = NumberUtils.tryParseDouble(_amountController.text) ?? 0.0;
      final litrosValue = _isCombustible ? NumberUtils.tryParseDouble(_litrosController.text) : null;
      final odoValue = (_isCombustible && _destinoCombustible == 'CAMION')
          ? NumberUtils.tryParseDouble(_odometerController.text)
          : null;
      final horoValue = (_isCombustible && _destinoCombustible == 'AUXILIAR')
          ? NumberUtils.tryParseDouble(_horometroController.text)
          : null;

      // Buscar el vehículo correspondiente para vincular ID
      final vehicles = ref.read(vehiclesProvider).value ?? [];
      final matchedVehicle = vehicles.where((v) => v.patente == shift.patenteCamion).firstOrNull;
      final vehicleDocId = matchedVehicle?.id ?? '';

      // Cálculo automático de rendimiento de tramo si es Full Tank
      double? kmRecorridos;
      double? rendimientoTramo;
      double intermediateLiters = 0.0;
      double? variacionComputadorPct;
      final computerL100km = _isCombustible
          ? NumberUtils.tryParseDouble(_onboardComputerController.text)
          : null;

      if (_isCombustible && _isFullTank && matchedVehicle != null) {
        if (_destinoCombustible == 'CAMION' && odoValue != null && matchedVehicle.ultimoLlenadoKm != null) {
          kmRecorridos = (odoValue >= matchedVehicle.ultimoLlenadoKm!)
              ? (odoValue - matchedVehicle.ultimoLlenadoKm!)
              : null;

          // Sumar cargas intermedias ocurridas entre el último Full Tank y este Full Tank
          if (matchedVehicle.ultimoLlenadoFecha != null) {
            final allExpenses = ref.read(allExpensesProvider).value ??
                ref.read(monthlyExpensesProvider).value ?? [];
            for (final exp in allExpenses) {
              if (exp.type.toLowerCase() == 'combustible' &&
                  (exp.vehicleId == matchedVehicle.id || exp.vehicleId == matchedVehicle.patente) &&
                  exp.destinoCombustible == 'CAMION' &&
                  !exp.isFullTank &&
                  exp.date.isAfter(matchedVehicle.ultimoLlenadoFecha!)) {
                intermediateLiters += (exp.litros ?? 0.0);
              }
            }
          }

          final totalLiters = intermediateLiters + (litrosValue ?? 0.0);
          if (kmRecorridos != null && totalLiters > 0) {
            rendimientoTramo = double.parse((kmRecorridos / totalLiters).toStringAsFixed(2));

            // Comparar con el computador a bordo si el chofer lo ingresó
            if (computerL100km != null && computerL100km > 0) {
              final computerKmPorLitro = 100.0 / computerL100km;
              variacionComputadorPct = double.parse(
                  (((rendimientoTramo - computerKmPorLitro) / computerKmPorLitro) * 100.0).toStringAsFixed(1));
            }
          }
        }
      }

      final newExpense = ExpenseModel(
        id: 'EXP-${DateTime.now().millisecondsSinceEpoch}',
        idEmpresa: user.idEmpresa,
        idChofer: user.uid,
        idJornada: shift.id,
        tripId: null,
        amount: amountValue,
        type: _selectedType,
        litros: litrosValue,
        date: DateTime.now(),
        description: _descriptionController.text,
        status: 'Pendiente',
        vehicleId: vehicleDocId,
        destinoCombustible: _isCombustible ? _destinoCombustible : null,
        isFullTank: _isCombustible ? _isFullTank : false,
        odometerAtFill: odoValue,
        horometroAtFill: horoValue,
        kmRecorridosTramo: kmRecorridos,
        rendimientoTramo: rendimientoTramo,
        litrosCargasIntermedias: intermediateLiters > 0 ? intermediateLiters : null,
        onboardComputerL100km: computerL100km,
        variacionComputadorPct: variacionComputadorPct,
        isExento: _isExento,
      );

      await ref.read(tripRepositoryProvider).addExpense(newExpense);

      // Si fue Full Tank o actualizó odómetro, actualizamos el vehículo en el repositorio
      if (_isCombustible && matchedVehicle != null) {
        final updatedVehicle = matchedVehicle.copyWith(
          currentOdometer: odoValue ?? matchedVehicle.currentOdometer,
          tanqueCalibrado: _isFullTank ? true : matchedVehicle.tanqueCalibrado,
          ultimoLlenadoKm: (_isFullTank && _destinoCombustible == 'CAMION' && odoValue != null)
              ? odoValue
              : matchedVehicle.ultimoLlenadoKm,
          ultimoLlenadoFecha: _isFullTank ? DateTime.now() : matchedVehicle.ultimoLlenadoFecha,
          horometroActualAuxiliar: horoValue ?? matchedVehicle.horometroActualAuxiliar,
          ultimoLlenadoHorometroAux: (_isFullTank && _destinoCombustible == 'AUXILIAR' && horoValue != null)
              ? horoValue
              : matchedVehicle.ultimoLlenadoHorometroAux,
          ultimoRendimientoReal: rendimientoTramo ?? matchedVehicle.ultimoRendimientoReal,
          ultimoComputadorAbordoL100km: computerL100km ?? matchedVehicle.ultimoComputadorAbordoL100km,
          factorCorreccionComputador: (computerL100km != null && computerL100km > 0 && rendimientoTramo != null)
              ? double.parse((rendimientoTramo / (100.0 / computerL100km)).toStringAsFixed(3))
              : matchedVehicle.factorCorreccionComputador,
        );
        try {
          await ref.read(adminRepositoryProvider).updateVehicle(updatedVehicle);
        } catch (_) {
          // Si el chofer no tiene permisos directos sobre flota, el gasto queda registrado
        }
      }

      if (!mounted) return;
      String snackMsg = 'Gasto registrado exitosamente';
      if (rendimientoTramo != null) {
        final l100 = (100.0 / rendimientoTramo).toStringAsFixed(1);
        snackMsg = '¡Full Tank! Rendimiento real: $rendimientoTramo km/L ($l100 L/100km)';
        if (variacionComputadorPct != null) {
          snackMsg += ' • Dif. tablero: ${variacionComputadorPct > 0 ? "+$variacionComputadorPct" : "$variacionComputadorPct"}%';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            snackMsg,
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFFFFFFFF),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = ref.watch(activeShiftProvider).value;
    final vehicles = ref.watch(vehiclesProvider).value ?? [];
    final matchedVehicle = vehicles.where((v) => v.patente == shift?.patenteCamion).firstOrNull;

    // Precargar odómetro sugerido si no lo ha ingresado
    if (_odometerController.text.isEmpty && matchedVehicle != null && matchedVehicle.currentOdometer > 0) {
      _odometerController.text = matchedVehicle.currentOdometer.toStringAsFixed(0);
    }
    if (_horometroController.text.isEmpty &&
        matchedVehicle != null &&
        matchedVehicle.horometroActualAuxiliar != null &&
        matchedVehicle.horometroActualAuxiliar! > 0) {
      _horometroController.text = matchedVehicle.horometroActualAuxiliar!.toStringAsFixed(1);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Gasto', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tipo de Gasto',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedType,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E1E1E),
                      items: _expenseTypes.map((String type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedType = newValue;
                            // Peaje es exento por defecto, otros con IVA
                            if (_selectedType == 'Peaje') {
                              _isExento = true;
                            } else {
                              _isExento = false;
                            }
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // REGIMEN TRIBUTARIO (EXENTO VS CON IVA)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isExento ? Colors.blueGrey : Colors.greenAccent.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isExento ? Icons.receipt_long : Icons.verified,
                        color: _isExento ? Colors.grey : Colors.greenAccent,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isExento ? 'Documento Exento de IVA' : 'Factura / Boleta Afecta a IVA (19%)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isExento ? Colors.white70 : Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              _isExento
                                  ? '100% costo puro, sin crédito fiscal (Peajes, romanas, etc.)'
                                  : 'El sistema separará el neto y recuperará el IVA crédito',
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: !_isExento,
                        activeThumbColor: Colors.greenAccent,
                        inactiveThumbColor: Colors.grey,
                        onChanged: (conIva) {
                          setState(() => _isExento = !conIva);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // SI ES COMBUSTIBLE: SELECCIÓN DE ESTANQUE DESTINO & FULL TANK
                if (_isCombustible) ...[
                  // Selector de Estanque (Camión vs Equipo Auxiliar/Thermo King)
                  if (matchedVehicle != null && matchedVehicle.tieneEquipoAuxiliar) ...[
                    const Text(
                      'Estanque Destino',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _destinoCombustible = 'CAMION'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _destinoCombustible == 'CAMION'
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _destinoCombustible == 'CAMION'
                                      ? Colors.white
                                      : Colors.white12,
                                  width: _destinoCombustible == 'CAMION' ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.local_shipping,
                                    color: _destinoCombustible == 'CAMION' ? Colors.white : Colors.grey,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Camión (${matchedVehicle.patente})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _destinoCombustible == 'CAMION' ? Colors.white : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _destinoCombustible = 'AUXILIAR'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _destinoCombustible == 'AUXILIAR'
                                    ? Colors.cyanAccent.withValues(alpha: 0.12)
                                    : const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _destinoCombustible == 'AUXILIAR'
                                      ? Colors.cyanAccent
                                      : Colors.white12,
                                  width: _destinoCombustible == 'AUXILIAR' ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.ac_unit,
                                    color: _destinoCombustible == 'AUXILIAR'
                                        ? Colors.cyanAccent
                                        : Colors.grey,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    matchedVehicle.identificadorAuxiliar ?? 'Thermo King / Reefer',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _destinoCombustible == 'AUXILIAR'
                                          ? Colors.cyanAccent
                                          : Colors.grey,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // SWITCH FULL TANK (LLENADO A TOPE / CALIBRACIÓN)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isFullTank ? Colors.green.withValues(alpha: 0.12) : const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isFullTank ? Colors.greenAccent : Colors.white12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.local_gas_station,
                          color: _isFullTank ? Colors.greenAccent : Colors.grey,
                          size: 30,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                matchedVehicle?.tanqueCalibrado == false
                                    ? '⭐ Calibración Inicial (Lleno a Tope)'
                                    : 'Estanque Lleno (Full Tank)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                matchedVehicle?.tanqueCalibrado == false
                                    ? 'Obligatorio para calibrar el estanque digital al 100%'
                                    : 'Calcula rendimiento real y calibra el estanque al 100%',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isFullTank,
                          activeThumbColor: Colors.greenAccent,
                          onChanged: (val) {
                            setState(() => _isFullTank = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                const Text(
                  'Monto Pagado',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalTextInputFormatter()],
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFFFFFFF)),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFFFFF), width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor ingrese un monto';
                    }
                    if (NumberUtils.tryParseDouble(value) == null) {
                      return 'Monto inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                if (_isCombustible) ...[
                  const Text(
                    'Litros Cargados',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _litrosController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [DecimalTextInputFormatter()],
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFE0E0E0)),
                    decoration: InputDecoration(
                      suffixText: 'L',
                      suffixStyle: const TextStyle(fontSize: 20, color: Colors.white54),
                      hintText: 'Ej: 350.0',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 20),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (_isCombustible && (value == null || value.isEmpty)) {
                        return 'Ingrese litros';
                      }
                      if (value != null && value.isNotEmpty && NumberUtils.tryParseDouble(value) == null) {
                        return 'Formato inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Si carga en camión: Odómetro
                  if (_destinoCombustible == 'CAMION') ...[
                    const Text(
                      'Odómetro Tablero (KM)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _odometerController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [DecimalTextInputFormatter()],
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      decoration: InputDecoration(
                        suffixText: 'KM',
                        suffixStyle: const TextStyle(fontSize: 16, color: Colors.white54),
                        hintText: 'Ej: 145200',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 18),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (value) {
                        if (_isCombustible && _destinoCombustible == 'CAMION' && (value == null || value.isEmpty)) {
                          return 'Ingrese el kilometraje del tablero';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Entrada opcional de lectura de Computador a Bordo (Tablero CAN)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161E2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.display_settings, color: Color(0xFF38BDF8), size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Computador a Bordo (Tablero CAN)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('Opcional', style: TextStyle(color: Colors.white60, fontSize: 10)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Ingresa el consumo promedio que marca el tablero (ej: 34.1 L/100km) para contrastar con la realidad.',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _onboardComputerController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [DecimalTextInputFormatter()],
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                            decoration: InputDecoration(
                              suffixText: 'L / 100 km',
                              suffixStyle: const TextStyle(fontSize: 14, color: Colors.white60),
                              hintText: 'Ej: 34.1',
                              hintStyle: const TextStyle(color: Colors.white30, fontSize: 16),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Si carga en generador auxiliar: Horómetro
                  if (_destinoCombustible == 'AUXILIAR') ...[
                    const Text(
                      'Horómetro Generador / Frío (Horas)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _horometroController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [DecimalTextInputFormatter()],
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                      decoration: InputDecoration(
                        suffixText: 'Horas',
                        suffixStyle: const TextStyle(fontSize: 16, color: Colors.cyanAccent),
                        hintText: 'Ej: 3450.5',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 18),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (value) {
                        if (_isCombustible && _destinoCombustible == 'AUXILIAR' && (value == null || value.isEmpty)) {
                          return 'Ingrese las horas del horómetro';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ],

                const Text(
                  'Descripción (Opcional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Ej: Copec Curicó / Carga completa',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFFFFF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text(
                      'GUARDAR GASTO',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
