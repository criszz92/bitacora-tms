import 'package:flutter/material.dart';

/// Paleta cromática de alta precisión para estética de instrumentación automotriz pesada
class AppColors {
  // Fondos y Superficies (Carbón profundo)
  static const Color background = Color(0xFF0B0D10);
  static const Color backgroundSecondary = Color(0xFF12151B);
  static const Color surface = Color(0xFF161A22);
  static const Color surfaceElevated = Color(0xFF1E2430);
  static const Color surfaceGlass = Color(0xA6161A22); // 65% opacidad

  // Acentos Ámbar e Industrial
  static const Color primary = Color(0xFFF59E0B); // Ámbar industrial vibrante
  static const Color primaryWarm = Color(0xFFFB923C); // Naranja cálido
  static const Color primaryDark = Color(0xFFD97706); // Ámbar profundo
  static const Color primaryAccent = Color(0xFFEA580C); // Naranja quemado

  // Textos y Jerarquía
  static const Color textPrimary = Color(0xFFF8FAFC); // Blanco hueso
  static const Color textSecondary = Color(0xFF94A3B8); // Gris plata
  static const Color textMuted = Color(0xFF64748B); // Gris pizarra

  // Estados Semánticos
  static const Color success = Color(0xFF10B981); // Verde esmeralda (Jornada abierta / OK)
  static const Color warning = Color(0xFFF59E0B); // Ámbar (Advertencias)
  static const Color error = Color(0xFFEF4444); // Rojo coral (Cierre / Crítico)
  static const Color info = Color(0xFF38BDF8); // Azul cian (Informativo / Técnico)
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.primaryWarm,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.background,
        onSecondary: AppColors.background,
        onSurface: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white10, width: 0.8),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
        labelSmall: TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
