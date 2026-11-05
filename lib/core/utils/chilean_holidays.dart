/// Utilidad oficial para cálculo de días hábiles comerciales en Chile.
/// Regla estricta: Lunes a Sábado, excluyendo Domingos y Feriados oficiales de Chile.
class ChileanHolidays {
  /// Lista de feriados oficiales nacionales de Chile (2025 - 2027)
  static final Set<String> _feriadosOficiales = {
    // 2025
    '2025-01-01', // Año Nuevo
    '2025-04-18', // Viernes Santo
    '2025-04-19', // Sábado Santo
    '2025-05-01', // Día del Trabajo
    '2025-05-21', // Día de las Glorias Navales
    '2025-06-20', // Día Nacional de los Pueblos Indígenas
    '2025-06-29', // San Pedro y San Pablo
    '2025-07-16', // Día de la Virgen del Carmen
    '2025-08-15', // Asunción de la Virgen
    '2025-09-18', // Fiestas Patrias
    '2025-09-19', // Día de las Glorias del Ejército
    '2025-10-12', // Encuentro de Dos Mundos
    '2025-10-31', // Día de las Iglesias Evangélicas
    '2025-11-01', // Día de Todos los Santos
    '2025-12-08', // Inmaculada Concepción
    '2025-12-25', // Navidad

    // 2026
    '2026-01-01', // Año Nuevo
    '2026-04-03', // Viernes Santo
    '2026-04-04', // Sábado Santo
    '2026-05-01', // Día del Trabajo
    '2026-05-21', // Glorias Navales
    '2026-06-21', // Pueblos Indígenas
    '2026-06-29', // San Pedro y San Pablo
    '2026-07-16', // Virgen del Carmen
    '2026-08-15', // Asunción de la Virgen
    '2026-09-18', // Fiestas Patrias
    '2026-09-19', // Glorias del Ejército
    '2026-10-12', // Encuentro de Dos Mundos
    '2026-10-31', // Iglesias Evangélicas
    '2026-11-01', // Todos los Santos
    '2026-12-08', // Inmaculada Concepción
    '2026-12-25', // Navidad

    // 2027
    '2027-01-01',
    '2027-03-26',
    '2027-03-27',
    '2027-05-01',
    '2027-05-21',
    '2027-06-21',
    '2027-06-28',
    '2027-07-16',
    '2027-08-15',
    '2027-09-17',
    '2027-09-18',
    '2027-10-11',
    '2027-10-31',
    '2027-11-01',
    '2027-12-08',
    '2027-12-25',
  };

  /// Verifica si una fecha dada es feriado oficial en Chile
  static bool isFeriado(DateTime date) {
    final key = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    return _feriadosOficiales.contains(key);
  }

  /// Verifica si un día es hábil operativo en Chile para transporte (Lunes a Sábado, no feriado)
  static bool isDiaHabilTransporte(DateTime date) {
    if (date.weekday == DateTime.sunday) return false;
    return !isFeriado(date);
  }

  /// Calcula los días hábiles de transporte (Lunes a Sábado sin feriados) en un mes completo
  static int getDiasHabilesMes(int year, int month) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    int count = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      if (isDiaHabilTransporte(DateTime(year, month, d))) {
        count++;
      }
    }
    return count;
  }

  /// Calcula los días hábiles detenidos entre dos fechas (inclusive)
  static int getDiasDetenidosHabiles(DateTime start, DateTime? end) {
    final actualEnd = end ?? DateTime.now();
    DateTime curr = DateTime(start.year, start.month, start.day);
    final limit = DateTime(actualEnd.year, actualEnd.month, actualEnd.day);

    if (curr.isAfter(limit)) return 0;

    int days = 0;
    while (!curr.isAfter(limit)) {
      if (isDiaHabilTransporte(curr)) {
        days++;
      }
      curr = curr.add(const Duration(days: 1));
    }
    return days;
  }
}

