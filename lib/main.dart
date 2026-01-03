import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:money_mint2/screens/profile/user_settings_screen.dart';
import 'package:provider/provider.dart';
import 'services/firebase_service.dart';
import 'services/admin_auth_service.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/blocked_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/pattern_verification_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/transactions/transaction_history_screen.dart';
import 'screens/transactions/add_transaction_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/budget/budget_screen.dart';
import 'screens/export/export_screen.dart';
import 'screens/bank_accounts/bank_accounts_screen.dart';
import 'screens/admin/admin_splash_screen.dart';
import 'screens/admin/admin_login_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/admin_replies_screen.dart';
import 'screens/support/replies_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  await Firebase.initializeApp();
  await FirebaseService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        StreamProvider<User?>(
          create: (_) => FirebaseService.authStateChanges,
          initialData: FirebaseService.currentUser,
          updateShouldNotify: (previous, current) => previous != current,
        ),
        Provider<AdminAuthService>(create: (_) => AdminAuthService()),
      ],
      child: MaterialApp(
        title: 'Money Mint',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.light(
            primary: const Color(0xFF274647),
            primaryContainer: const Color(0xFF1A3333),
            secondary: const Color(0xFF274647),
            secondaryContainer: const Color(0xFF1A3333),
            surface: Colors.white,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF274647),
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            titleTextStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          scaffoldBackgroundColor: const Color(0xFFC9D6D9),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: Colors.white,
            margin: const EdgeInsets.all(8),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF274647),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            hintStyle: TextStyle(color: Colors.grey[600]),
            labelStyle: const TextStyle(color: Color(0xFF274647)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(
                color: Color(0xFF274647),
                width: 1.5,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/blocked': (context) => const BlockedScreen(),
          '/home': (context) => const HomeScreen(),
          '/transactions': (context) => const TransactionHistoryScreen(),
          '/transaction': (context) => const AddTransactionScreen(),
          '/budget': (context) => const BudgetScreen(),
          '/bank-accounts': (context) => const BankAccountsScreen(),
          '/profile': (context) => const ProfileScreen(),
          '/export': (context) => const ExportScreen(),
          '/support/replies': (context) => const RepliesScreen(),

          // Admin routes
          '/admin': (context) => const AdminSplashScreen(),
          '/admin/login': (context) => const AdminLoginScreen(),
          '/admin/dashboard': (context) => const AdminDashboardScreen(),
          '/admin/replies': (context) => const AdminRepliesScreen(),
          '/pattern-verify': (context) => const PatternVerificationScreen(),
          '/settings': (context) => const UserSettingsScreen(),
        },
        onGenerateRoute: (settings) {
          // Handle auth route
          if (settings.name == '/auth') {
            return MaterialPageRoute(builder: (context) => const LoginScreen());
          }

          // Handle blocked user when navigating to any route
          if (settings.name != '/blocked' &&
              settings.name != '/login' &&
              settings.name != '/register') {
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              return MaterialPageRoute(
                builder: (context) => FutureBuilder<bool>(
                  future: FirebaseService.isCurrentUserBlocked(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done) {
                      if (snapshot.data == true) {
                        return const BlockedScreen();
                      }
                      // Return the requested screen if user is not blocked
                      // Check if pattern lock is enabled
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(currentUser.uid)
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.done) {
                            final isPatternEnabled =
                                snapshot.data?['patternLockEnabled'] ?? false;

                            // If pattern lock is enabled, show pattern verification
                            if (isPatternEnabled &&
                                settings.name != '/pattern-verify') {
                              return const PatternVerificationScreen();
                            }

                            // Otherwise, show the requested screen
                            switch (settings.name) {
                              case '/home':
                                return const HomeScreen();
                              case '/transactions':
                                return const TransactionHistoryScreen();
                              case '/budget':
                                return const BudgetScreen();
                              case '/profile':
                                return const ProfileScreen();
                              case '/export':
                                return const ExportScreen();
                              case '/bank-accounts':
                                return const BankAccountsScreen();
                              default:
                                return const HomeScreen();
                            }
                          }
                          // Show loading while checking pattern status
                          return const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          );
                        },
                      );
                    }
                    // Show loading indicator while checking user status
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  },
                ),
              );
            }
            // If user is not logged in, redirect to login
            if (settings.name != '/login' && settings.name != '/register') {
              return MaterialPageRoute(
                builder: (context) => const LoginScreen(),
              );
            }
          }

          // Handle admin routes - let the named routes handle admin navigation
          if (settings.name?.startsWith('/admin') ?? false) {
            return null;
          }

          // If no route was matched, return a 404 page
          return MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Page Not Found')),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '404 - Page not found',
                      style: TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, '/'),
                      child: const Text('Go to Home'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
