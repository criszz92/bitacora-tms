import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/trip_provider.dart';
import '../../domain/models/expense_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/utils/number_utils.dart';

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
  final _descriptionController = TextEditingController();
  String _selectedType = 'Peaje';

  final List<String> _expenseTypes = ['Peaje', 'Combustible'];

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
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      final user = ref.read(currentUserProfileProvider).value;
      final shift = ref.read(activeShiftProvider).value;

      if (user == null || shift == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: No hay jornada activa para asociar este gasto.'), backgroundColor: Colors.red),
        );
        return;
      }

      // Parseo seguro de números usando la nueva utilidad
      final amountValue = NumberUtils.tryParseDouble(_amountController.text) ?? 0.0;
      final litrosValue = _isCombustible ? NumberUtils.tryParseDouble(_litrosController.text) : null;

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
        vehicleId: shift.patenteCamion,
      );

      await ref.read(tripRepositoryProvider).addExpense(newExpense);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gasto registrado exitosamente', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Color(0xFFFFFFFF),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Monto',
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
                      hintText: 'Ej: 120.5',
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
                ],
                const Text(
                  'Descripción (Opcional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Ej: Peaje Angostura / Carga de Diesel',
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
                    child: const Text('GUARDAR GASTO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
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
