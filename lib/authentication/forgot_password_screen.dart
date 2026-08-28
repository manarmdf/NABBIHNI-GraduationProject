import 'package:flutter/material.dart';
import '../shared/constants.dart';
import 'auth_service.dart';

// شاشة استعادة كلمة المرور للمستخدمين الذين نسوا كلمات المرور الخاصة بهم.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isLoading = false;

  // تنظيف وحدات التحكم بالحقول عند إغلاق الشاشة لتجنب تسرب الذاكرة.
  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // التحقق من النموذج ومحاولة إرسال بريد استعادة كلمة المرور، مع عرض رسالة النجاح أو الخطأ.
  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final error = await AuthService.resetPassword(
      _emailController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent. Please check your inbox.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: AppColors.textPrimary),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/images/logo2.png',
                    width: 200,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Reset Password',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your email address and we will send you a link to reset your password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 40),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email.';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _resetPassword,
                          child: const Text('Send Reset Link'),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
