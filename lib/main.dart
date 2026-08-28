import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'authentication/login_screen.dart';
import 'firebase_options.dart';
import 'home/home_screen.dart';
import 'shared/app_theme.dart';
import 'shared/constants.dart';
import 'shared/notifications.dart';
import 'splash/splash_screen.dart';

bool _firebaseReady = false;

// نقطة بداية التطبيق: تهيئة الإشعارات والمناطق الزمنية وفايربيس قبل التشغيل.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await initNotifications();
  await AppConfig.loadRadius();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    _firebaseReady = true;
  } catch (_) {
    _firebaseReady = false;
  }
  runApp(const NabbihniApp());
}

// الويدجت الرئيسي للتطبيق الذي يحدد الثيم والشاشة الأولى.
class NabbihniApp extends StatelessWidget {
  const NabbihniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nabbihni',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _firebaseReady ? const _SplashGate() : const _FirebaseSetupScreen(),
    );
  }
}

class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const _AuthGate()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}

// بوابة المصادقة: تنقل المستخدم بين شاشة الدخول والشاشة الرئيسية حسب حالة الدخول.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        if (snapshot.hasData) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

// شاشة احتياطية تظهر عند عدم تهيئة فايربيس بعد.
class _FirebaseSetupScreen extends StatelessWidget {
  const _FirebaseSetupScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 60, color: AppColors.warning),
              const SizedBox(height: 20),
              const Text(
                'Firebase not configured',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Follow these steps once, then rebuild the app:',
                style: TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              _Step(
                number: '1',
                text:
                    'Go to console.firebase.google.com → create a project named "nabbihni".',
              ),
              _Step(
                number: '2',
                text:
                    'In a terminal, run:\n\ndart pub global activate flutterfire_cli\nflutterfire configure',
              ),
              _Step(
                number: '3',
                text:
                    'This generates lib/firebase_options.dart.\nThen update main.dart as shown in the comment at the top.',
              ),
              _Step(
                number: '4',
                text:
                    'Enable Email/Password and Google sign-in in Firebase Console → Authentication.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// عنصر مرقّم يستخدم في عرض خطوات إعداد فايربيس.
class _Step extends StatelessWidget {
  final String number;
  final String text;
  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary,
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
