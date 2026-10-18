import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'firebase_options.dart';
import 'features/trips/domain/services/fuzzy_search_service.dart';
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

  runApp(
    ProviderScope(
      overrides: [
        // Inyectamos la instancia ya inicializada en el árbol de providers.
        fuzzySearchProvider.overrideWithValue(fuzzyService),
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
