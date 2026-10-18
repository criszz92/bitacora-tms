import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'firebase_options.dart';
import 'features/trips/domain/services/fuzzy_search_service.dart';
import 'features/trips/domain/services/distance_service.dart';
import 'core/services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CL', null);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Inicializar Notificaciones Push solo en móvil
  if (!kIsWeb) {
    await PushNotificationService.initialize();
  }

  // Pre-carga los 3.647 clientes de Ziyu en RAM al iniciar la app.
  // Esto garantiza que el Fuzzy Search sea instantáneo desde el primer uso,
  // incluso sin conexión a internet.
  final fuzzyService = FuzzySearchService();
  await fuzzyService.loadClientsFromAsset('assets/clientes_limpio_mayusculas.txt');

  // Pre-carga la tabla de distancias cliente-puerto (1.376 entradas) en RAM.
  // Permite sugerir KM estimados automáticamente al cerrar un viaje.
  final distanceService = DistanceService();
  await distanceService.loadFromAsset('assets/distancias_clientes.json');

  runApp(
    ProviderScope(
      overrides: [
        // Inyectamos las instancias ya inicializadas en el árbol de providers.
        fuzzySearchProvider.overrideWithValue(fuzzyService),
        distanceServiceProvider.overrideWithValue(distanceService),
      ],
      child: const BitacoraApp(),
    ),
  );
}

class BitacoraApp extends ConsumerWidget {
  const BitacoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'HEIRLOG-TMS',
      theme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
