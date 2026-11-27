import 'dart:io';
import '../../../../core/utils/tms_backbone.dart';
import '../../../trips/domain/models/trip_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/domain/models/user_model.dart';
import '../../../trips/presentation/providers/trip_provider.dart';
import '../../../../core/theme/app_theme.dart';

class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  ConsumerState<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  String? _localPhotoPath;
  
  @override
  void initState() {
    super.initState();
    _loadLocalProfilePhoto();
  }

  Future<void> _loadLocalProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final user = ref.read(currentUserProfileProvider).value;
    if (user != null) {
      final savedPath = prefs.getString('driver_photo_${user.uid}');
      if (mounted) {
        setState(() => _localPhotoPath = savedPath);
      }
    } else {
      
    }
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final user = ref.read(currentUserProfileProvider).value;
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('driver_photo_${user.uid}', path);
        }
        if (mounted) {
          setState(() => _localPhotoPath = path);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF10B981),
              content: Text('Foto de perfil actualizada correctamente'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Error al seleccionar imagen: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProfileProvider);
    final tripsAsync = ref.watch(activeTripsProvider);
    final user = userAsync.value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'FICHA DEL CONDUCTOR',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildHeaderAvatar(user),
                  const SizedBox(height: 20),
                  _buildDocumentAlertsBanner(user),
                  const SizedBox(height: 16),
                  _buildInfoCard(user),
                  const SizedBox(height: 16),
                  _buildRoadMasterScoreCard(tripsAsync),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ── 1. AVATAR & IDENTIFICACIÓN ──────────────────────────────────────────────

  Widget _buildHeaderAvatar(UserModel user) {
    ImageProvider? imageProvider;
    if (_localPhotoPath != null && File(_localPhotoPath!).existsSync()) {
      imageProvider = FileImage(File(_localPhotoPath!));
    } else if (user.fotoPerfilUrl != null && user.fotoPerfilUrl!.isNotEmpty) {
      imageProvider = NetworkImage(user.fotoPerfilUrl!);
    }

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFFD97706), AppColors.surfaceElevated],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 54,
                backgroundColor: AppColors.surface,
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? const Icon(Icons.person, size: 58, color: Colors.white38)
                    : null,
              ),
            ),
            GestureDetector(
              onTap: _pickProfilePhoto,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 2),
                ),
                child: const Icon(Icons.camera_alt, color: AppColors.background, size: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          user.nombre.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          user.rut ?? 'RUT No Registrado',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            'EMPRESA: ${user.idEmpresa.toUpperCase()}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  // ── 2. ALERTAS PREVENTIVAS DE DOCUMENTACIÓN ─────────────────────────────────

  Widget _buildDocumentAlertsBanner(UserModel user) {
    final licAlert = _evaluateDocDate(user.fechaVencimientoLicencia, 'Licencia de Conducir');
    final ciAlert = _evaluateDocDate(user.fechaVencimientoCedula, 'Cédula de Identidad');

    final alerts = [licAlert, ciAlert].where((a) => a != null).cast<_DocStatus>().toList();

    if (alerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_user_outlined, color: Color(0xFF10B981), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Documentación legal al día y verificada.',
                style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: alerts.map((alert) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: alert.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: alert.color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(alert.icon, color: alert.color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title.toUpperCase(),
                      style: TextStyle(
                        color: alert.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.message,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  _DocStatus? _evaluateDocDate(DateTime? date, String docName) {
    if (date == null) return null;
    final now = DateTime.now();
    final diff = date.difference(now).inDays;
    final formatted = DateFormat('dd/MM/yyyy').format(date);

    if (diff < 0) {
      return _DocStatus(
        title: '$docName Vencida',
        message: 'Expiró el $formatted. Notifica de urgencia a administración.',
        color: Colors.redAccent,
        icon: Icons.dangerous_outlined,
      );
    } else if (diff <= 30) {
      return _DocStatus(
        title: 'Atención: $docName por vencer',
        message: 'Vence en $diff días ($formatted). Gestiona la renovación preventiva.',
        color: AppColors.primary,
        icon: Icons.warning_amber_rounded,
      );
    }
    return null;
  }

  // ── 3. DATOS DE OPERACIÓN (TARJETA ESPACIOSA Y CLARA) ───────────────────────────

  Widget _buildInfoCard(UserModel user) {
    final licText = (user.licencias != null && user.licencias!.isNotEmpty)
        ? user.licencias!.join(', ')
        : 'No Registrada';

    final fLic = user.fechaVencimientoLicencia != null
        ? DateFormat('dd/MM/yyyy').format(user.fechaVencimientoLicencia!)
        : 'Sin fecha asignada';

    final fCI = user.fechaVencimientoCedula != null
        ? DateFormat('dd/MM/yyyy').format(user.fechaVencimientoCedula!)
        : 'Sin fecha asignada';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161A22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.badge_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DATOS DE HABILITACIÓN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  Text(
                    'Registro oficial del conductor',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'OFICIAL',
                  style: TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _infoRow('Clase de Licencia', licText, Icons.drive_eta_outlined, Colors.amberAccent),
          const Divider(color: Colors.white12, height: 26),
          _infoRow('Vencimiento Licencia', fLic, Icons.calendar_month_outlined, Colors.blueAccent),
          const Divider(color: Colors.white12, height: 26),
          _infoRow('Vencimiento Cédula', fCI, Icons.credit_card_outlined, Colors.purpleAccent),
          const Divider(color: Colors.white12, height: 26),
          _infoRow('Tracto Habitual', user.patenteAsignada ?? 'Por asignar', Icons.local_shipping_outlined, Colors.orangeAccent),
          const Divider(color: Colors.white12, height: 26),
          _infoRow('Tipo de Contrato', user.tipoContrato ?? 'Indefinido', Icons.description_outlined, Colors.greenAccent),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, IconData icon, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. ROAD MASTER SCORE (AMPLIO Y LEGIBLE) ───────────────────────────────

  Widget _buildRoadMasterScoreCard(AsyncValue tripsAsync) {
    final trips = (tripsAsync.value as List?)?.cast<TripModel>() ?? <TripModel>[];
    final score = TmsBackbone.calculateRoadMasterScore(driverTrips: trips);
    final int totalScore = score.total;
    final int hitosScore = score.hitos;
    final int combustibleScore = score.combustible;
    final int jornadaScore = score.jornada;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161A22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.workspace_premium_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ROAD MASTER SCORE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        'Desempeño y cuidado operacional',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary),
                ),
                child: Text(
                  '$totalScore / 100 PTS',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Calificación de consistencia y cuidado operacional en ruta basada en tus registros.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 22),
          _scoreBar('Cumplimiento de Hitos en Ruta', hitosScore, 40, const Color(0xFF10B981)),
          const SizedBox(height: 18),
          _scoreBar('Calibración de Combustible (Km/L)', combustibleScore, 30, AppColors.primary),
          const SizedBox(height: 18),
          _scoreBar('Conciliación Odómetro de Jornada', jornadaScore, 30, const Color(0xFF38BDF8)),
        ],
      ),
    );
  }

  Widget _scoreBar(String label, int current, int max, Color barColor) {
    final percent = (current / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: barColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$current / $max pts',
                style: TextStyle(color: barColor, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 8,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}

class _DocStatus {
  final String title;
  final String message;
  final Color color;
  final IconData icon;

  _DocStatus({
    required this.title,
    required this.message,
    required this.color,
    required this.icon,
  });
}

