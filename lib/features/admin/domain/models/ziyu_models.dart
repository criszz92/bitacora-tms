/// Representa una fila del Excel exportado desde el sistema Ziyu (Medlog).
/// El motor de conciliación intenta detectar las columnas automáticamente.
class ZiyuRecord {
  final int rowIndex;           // Número de fila original (para debug)
  final String? osNumber;       // Número de OS (Orden de Servicio)
  final String? containerNumber;// Número de contenedor
  final String? guideNumber;    // Número de guía/BL
  final String? origin;
  final String? destination;
  final String? client;
  final double? value;
  final DateTime? date;
  final String? vehiclePlate;   // Patente del vehículo reportada en Ziyu
  final String rawData;         // Fila completa como texto (para mostrar en UI)

  ZiyuRecord({
    required this.rowIndex,
    this.osNumber,
    this.containerNumber,
    this.guideNumber,
    this.origin,
    this.destination,
    this.client,
    this.value,
    this.date,
    this.vehiclePlate,
    required this.rawData,
  });

  /// Clave de búsqueda normalizada: elimina guiones, espacios y pone mayúsculas.
  /// Se usa para el cruce difuso con los viajes de Bitácora.
  String get normalizedContainer => normalize(containerNumber ?? '');
  String get normalizedOs => normalize(osNumber ?? '');
  String get normalizedGuide => normalize(guideNumber ?? '');
  String get normalizedPlate => normalize(vehiclePlate ?? '');

  static String normalize(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Lógica de comparación inteligente: ignora prefijos comunes y permite substring
  static bool isSmartMatch(String a, String b) {
    final ca = normalize(a);
    final cb = normalize(b);
    if (ca.isEmpty || cb.isEmpty) return false;
    if (ca == cb) return true;

    // 1. Comparar solo la parte numérica (Muy efectivo para GUIA123 vs 123)
    final na = ca.replaceAll(RegExp(r'[^0-9]'), '');
    final nb = cb.replaceAll(RegExp(r'[^0-9]'), '');
    if (na.isNotEmpty && na == nb && na.length >= 5) return true;

    // 2. Eliminar prefijos comunes (GUIA, VIAJE, OS, etc)
    final prefixes = RegExp(r'^(GUIA|GUI|G|VIAJE|OS|OT|REF)');
    final ra = ca.replaceFirst(prefixes, '');
    final rb = cb.replaceFirst(prefixes, '');
    
    if (ra.isNotEmpty && rb.isNotEmpty && ra == rb) return true;

    // 3. Substring match si la cadena es lo suficientemente larga
    if (ra.length >= 5 && rb.length >= 5) {
      if (ra.contains(rb) || rb.contains(ra)) return true;
    }

    return false;
  }
}

/// Resultado del cruce de un registro Ziyu contra los viajes de Bitácora.
enum ReconciliationStatus {
  matched,        // ✅ Encontrado en ambos lados
  warningPlate,   // 🚛 Contenedor coincide pero la PATENTE es distinta
  onlyInZiyu,     // ⚠️ En Ziyu pero el conductor no lo registró
  onlyInBitacora, // ❓ En Bitácora (tipo OS) pero no aparece en Ziyu
}

class ReconciliationResult {
  final ReconciliationStatus status;
  final ZiyuRecord? ziyuRecord;
  final dynamic tripModel;      // TripModel (dinámico para evitar dependencia circular)
  final String matchKey;        // Clave usada para el match (contenedor, guía u OS)
  final double? diferencia;     // Diferencia de valor si hay discrepancia

  ReconciliationResult({
    required this.status,
    this.ziyuRecord,
    this.tripModel,
    required this.matchKey,
    this.diferencia,
  });

  String get statusLabel => switch (status) {
    ReconciliationStatus.matched        => 'Conciliado',
    ReconciliationStatus.warningPlate   => 'Error de Patente',
    ReconciliationStatus.onlyInZiyu     => 'Solo en Ziyu',
    ReconciliationStatus.onlyInBitacora => 'Solo en Bitácora',
  };

  String get statusIcon => switch (status) {
    ReconciliationStatus.matched        => '✅',
    ReconciliationStatus.warningPlate   => '🚛⚠️',
    ReconciliationStatus.onlyInZiyu     => '⚠️',
    ReconciliationStatus.onlyInBitacora => '❓',
  };
}
