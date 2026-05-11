import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/driver/presentation/screens/driver_dashboard_screen.dart';
import '../../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../../features/trips/presentation/screens/expense_form_screen.dart';
import '../../features/trips/presentation/screens/shift_start_screen.dart';
import '../../features/trips/presentation/screens/trip_form_screen.dart';
import '../../features/trips/presentation/screens/retro_trip_form_screen.dart';
import '../../features/driver/presentation/screens/viaticos_request_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_profile_screen.dart';
import '../../features/driver/presentation/screens/monthly_summary_screen.dart';
import '../../features/trips/presentation/screens/trip_confirmation_screen.dart';
import '../../features/admin/domain/models/service_request_model.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final userProfileAsync = ref.watch(currentUserProfileProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isAuth = authState.value != null;
      final isLoggingIn = state.matchedLocation == '/login';

      // 1. Si Firebase Auth está cargando, esperamos.
      if (authState.isLoading) return null;

      // 2. Si no hay sesión y trata de ir a cualquier lado, va a login.
      if (!isAuth && !isLoggingIn) return '/login';

      // 3. Si hay sesión iniciada, evaluamos el ROL.
      if (isAuth) {
        // Esperamos a que el perfil se descargue de Firestore
        if (userProfileAsync.isLoading) return null;
        
        final user = userProfileAsync.value;
        final isRegisteringProfile = state.matchedLocation == '/register-profile';

        // Si está autenticado pero NO tiene documento en Firestore, lo obligamos a crear su perfil
        if (user == null) {
          if (!isRegisteringProfile) return '/register-profile';
          return null; // Si ya está en la pantalla de registro, lo dejamos ahí
        }

        // Si TIENE perfil pero intenta ir a la pantalla de registro, lo sacamos de ahí
        if (isRegisteringProfile) {
          return user.rol == 'ADMIN' ? '/admin' : '/driver';
        }

        final isDriverPath = state.matchedLocation.startsWith('/driver') || 
                             state.matchedLocation.startsWith('/add-expense') || 
                             state.matchedLocation == '/add-trip' || 
                             state.matchedLocation == '/retro-trip' || 
                             state.matchedLocation == '/viaticos-request' || 
                             state.matchedLocation == '/monthly-summary' || 
                             state.matchedLocation == '/start-shift';
        final isAdminPath = state.matchedLocation.startsWith('/admin');

        // REGLAS ESTRICTAS DE ROL
        if (user.rol == 'ADMIN') {
          // El Admin (Dueño de camión) tiene acceso total a ambos mundos.
          if (!isAdminPath && !isDriverPath) {
            // Si está en la Web (Computador), lo enviamos al Dashboard Administrativo.
            // Si está en la APK (Celular), lo enviamos directo al Dashboard de Chofer.
            return kIsWeb ? '/admin' : '/driver';
          }
        } else {
          // El Chofer NUNCA puede entrar a rutas de admin
          if (!isDriverPath) return '/driver';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register-profile',
        builder: (context, state) => const RegisterProfileScreen(),
      ),
      GoRoute(
        path: '/driver',
        builder: (context, state) => const DriverDashboardScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/add-expense',
        builder: (context, state) {
          final type = state.uri.queryParameters['type'];
          return ExpenseFormScreen(initialType: type);
        },
      ),
      GoRoute(
        path: '/viaticos-request',
        builder: (context, state) => const ViaticosRequestScreen(),
      ),
      GoRoute(
        path: '/add-trip',
        builder: (context, state) => const TripFormScreen(),
      ),
      GoRoute(
        path: '/start-shift',
        builder: (context, state) => const ShiftStartScreen(),
      ),
      GoRoute(
        path: '/retro-trip',
        builder: (context, state) => const RetroTripFormScreen(),
      ),
      GoRoute(
        path: '/monthly-summary',
        builder: (context, state) {
          final userId = state.uri.queryParameters['userId'];
          return MonthlySummaryScreen(userId: userId);
        },
      ),
      GoRoute(
        path: '/confirm-assigned-trip',
        builder: (context, state) {
          final request = state.extra as ServiceRequest;
          return TripConfirmationScreen(request: request);
        },
      ),
    ],
  );
});
