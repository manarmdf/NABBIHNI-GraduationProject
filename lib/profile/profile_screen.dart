import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../authentication/auth_service.dart';
import '../location/my_locations_screen.dart';
import '../shared/constants.dart';

/// شاشة الملف الشخصي — عرض وتعديل اسم المستخدم وإعدادات التطبيق.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  int _radius = AppConfig.nearbyRadiusMeters;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  /// يحمّل بيانات الملف الشخصي من Firestore.
  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (mounted) {
      setState(() {
        _profile = doc.data();
        _loading = false;
      });
    }
  }

  /// يفتح نافذة تعديل اسم المستخدم.
  Future<void> _editName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final controller = TextEditingController(text: user.displayName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Your name'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    await user.updateDisplayName(newName);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({'name': newName});
    await _loadProfile();
    if (mounted) setState(() {});
  }

  /// يفتح نافذة تعديل نصف قطر الكشف عن الأماكن القريبة.
  Future<void> _editRadius() async {
    final controller = TextEditingController(text: _radius.toString());
    int sliderValue = _radius.toDouble().clamp(
          AppConfig.minRadiusMeters.toDouble(),
          AppConfig.maxRadiusMeters.toDouble(),
        ).toInt();

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nearby Detection Radius'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Distance used to detect nearby places.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Slider(
                    value: sliderValue.toDouble(),
                    min: AppConfig.minRadiusMeters.toDouble(),
                    max: AppConfig.maxRadiusMeters.toDouble(),
                    divisions: 97,
                    label: _formatMeters(sliderValue),
                    onChanged: (v) => setLocal(() {
                      sliderValue = v.round();
                      controller.text = sliderValue.toString();
                    }),
                  ),
                ),
              ]),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(suffixText: 'm', isDense: true),
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed != null) {
                    setLocal(() => sliderValue = parsed.clamp(
                          AppConfig.minRadiusMeters, AppConfig.maxRadiusMeters));
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Min ${AppConfig.minRadiusMeters} m · Max ${AppConfig.maxRadiusMeters} m',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text) ?? sliderValue;
                Navigator.pop(ctx, parsed.clamp(
                    AppConfig.minRadiusMeters, AppConfig.maxRadiusMeters));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    await AppConfig.setRadius(result);
    if (!mounted) return;
    setState(() => _radius = AppConfig.nearbyRadiusMeters);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Radius set to ${_formatMeters(_radius)}')),
    );
  }

  /// يُنسّق المسافة بالأمتار أو الكيلومترات.
  static String _formatMeters(int m) =>
      m < 1000 ? '$m m' : '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km';

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final registeredAt = _profile?['registeredAt'];
    String memberSince = '';
    if (registeredAt is Timestamp) {
      final d = registeredAt.toDate();
      memberSince = '${d.day}/${d.month}/${d.year}';
    }
    final userType = _profile?['userType'] as String? ?? 'user';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primary,
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? const Icon(Icons.person_rounded, size: 48, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.displayName ?? 'User',
                    style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _InfoChip(label: userType.toUpperCase(), icon: Icons.badge_outlined),
                      if (memberSince.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        _InfoChip(label: 'Since $memberSince', icon: Icons.calendar_today_outlined),
                      ],
                    ],
                  ),
                  const SizedBox(height: 40),
                  OutlinedButton.icon(
                    onPressed: _editName,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Name'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MyLocationsScreen()),
                    ),
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('My Locations'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _editRadius,
                    icon: const Icon(Icons.near_me_outlined),
                    label: Text('Nearby Radius · ${_formatMeters(_radius)}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await AuthService.signOut();
                      if (mounted) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                    label: const Text('Sign Out', style: TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// شريحة معلومات صغيرة — تعرض تسمية مع أيقونة (نوع المستخدم / تاريخ التسجيل).
class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _InfoChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
        ],
      ),
    );
  }
}
