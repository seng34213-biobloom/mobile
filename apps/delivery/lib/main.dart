import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/auth_store.dart';
import 'app/api_client.dart';
import 'screens/login_screen.dart';
import 'screens/assignments_feed_screen.dart';

/// Bio Bloom Delivery — rider mobile app (SDS §2.1.1).
///
/// Auth: the rider logs in via /api/auth/login (DELIVERY-role JWT, 8 h TTL
/// per SDS §7.1). The JWT is stored in flutter_secure_storage (iOS Keychain
/// / Android Keystore — SDS §7 diagram). Subsequent requests carry the
/// `auth_token` cookie.
///
/// Screens:
///   • LoginScreen          — email + password.
///   • AssignmentsFeedScreen — list open assignments, transition statuses,
///                             upload proof, mark DELIVERED with GPS.
///   • ProofOfDeliveryScreen — camera capture + GPS, posts proof + status.
///
/// FCM token registration runs on first login (Phase 9 wires the actual
/// Firebase init).
void main() {
  runApp(const BiobloomDeliveryApp());
}

class BiobloomDeliveryApp extends StatelessWidget {
  const BiobloomDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => AuthStore()),
        ProxyProvider<AuthStore, ApiClient>(
          update: (_, auth, __) => ApiClient(auth),
        ),
      ],
      child: MaterialApp(
        title: 'Bio Bloom Delivery',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF557F41),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFFBF9F3),
        ),
        home: const _RootGate(),
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _loaded = false;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final auth = context.read<AuthStore>();
    final ok = await auth.hasToken();
    if (!mounted) return;
    setState(() {
      _signedIn = ok;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _signedIn
        ? const AssignmentsFeedScreen()
        : LoginScreen(onSignedIn: () => setState(() => _signedIn = true));
  }
}
