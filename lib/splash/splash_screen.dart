import 'package:flutter/material.dart';
import '../shared/constants.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        // Added an implicit animation for a premium fade-in/zoom-in effect
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOutQuint,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.95 + (0.05 * value),
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo2.png',
                width: 250, // Slightly increased to balance the larger circle
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 40), // Increased spacing for breathing room
              
              // Bigger, better circle
              const SizedBox(
                width: 56, // Increased from 36
                height: 56, // Increased from 36
                child: CircularProgressIndicator(
                  strokeWidth: 4.5, // Made slightly thicker to match the new size
                  color: AppColors.primary,
                  strokeCap: StrokeCap.round, // Gives the spinner rounded, modern edges
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}