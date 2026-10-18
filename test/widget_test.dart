import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/features/trips/domain/services/distance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DistanceService Unit Tests', () {
    late DistanceService service;

    setUp(() {
      service = DistanceService();
    });

    test('DistanceService starts uninitialized', () {
      expect(service.isLoaded, isFalse);
      expect(service.clientCount, 0);
      expect(service.lookupKm('Cualquiera', 'San Antonio'), isNull);
      expect(service.nearestPort('Cualquiera'), isNull);
    });

    test('DistanceService accurately resolves ports, aliases, and fallbacks', () {
      service.loadDataForTesting({
        'WALMART QUILICURA': {
          'puertoMasCercano': 'Pto San Antonio',
          'kmMinimo': 87.2,
          'distancias': {
            'Pto San Antonio': 87.2,
            'Pto Valparaiso': 90.3,
            'Pto San Vicente': 458.1,
            'Pto Coronel': 463.7,
            'Pto Lirquen': 426.5,
            'Pto Antofagasta': 1079.7,
          }
        }
      });

      expect(service.isLoaded, isTrue);
      expect(service.clientCount, 1);

      // Alias testing (case insensitive & spaces)
      expect(service.lookupKm('walmart quilicura', 'San Antonio'), 87.2);
      expect(service.lookupKm('WALMART QUILICURA', 'PTO SAN ANTONIO'), 87.2);
      expect(service.lookupKm(' WALMART QUILICURA ', 'puerto valparaiso '), 90.3);
      expect(service.lookupKm('walmart quilicura', 'Valparaíso'), 90.3);

      // Fallback when destination is not a known port alias
      expect(service.lookupKm('walmart quilicura', 'Bodega Central'), 87.2);

      // Unknown client returns null
      expect(service.lookupKm('CLIENTE INEXISTENTE', 'San Antonio'), isNull);

      // Nearest port
      expect(service.nearestPort('walmart quilicura'), 'Pto San Antonio');
      expect(service.nearestPort('DESCONOCIDO'), isNull);
    });
  });
}
