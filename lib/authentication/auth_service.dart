import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// خدمة المصادقة: تجمع كل عمليات الدخول والتسجيل والخروج في مكان واحد.
class AuthService {
  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;

  // تسجيل الدخول بالبريد وكلمة المرور، تُعيد رسالة خطأ عند الفشل أو null عند النجاح.
  static Future<String?> signInWithEmail(
      String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Login failed. Please try again.';
    }
  }

  // إنشاء حساب جديد وحفظ بيانات المستخدم في Firestore تحت users/{uid}.
  static Future<String?> registerWithEmail(
      String email, String password, String displayName) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password.trim());
      final user = credential.user!;
      await user.updateDisplayName(displayName.trim());

      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': displayName.trim(),
        'email': email.trim().toLowerCase(),
        'registeredAt': FieldValue.serverTimestamp(),
        'userType': 'user',
      });

      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Registration failed. Please try again.';
    } catch (_) {
      return 'Registration failed. Please try again.';
    }
  }

  // إرسال رابط استعادة كلمة المرور عبر البريد الإلكتروني.
  static Future<String?> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to send reset email. Please try again.';
    } catch (_) {
      return 'Failed to send reset email. Please try again.';
    }
  }

  // تسجيل خروج المستخدم الحالي من فايربيس.
  static Future<void> signOut() async {
    await _auth.signOut();
  }
}
