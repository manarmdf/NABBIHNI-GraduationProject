import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../shared/constants.dart';
import 'user_locations_service.dart';
import 'location_picker_screen.dart';
import 'nominatim_service.dart';

// شاشة إعداد وتعديل مواقع المستخدم الشخصية (المنزل، النادي، العمل، المدرسة).
class MyLocationsScreen extends StatefulWidget {
  const MyLocationsScreen({super.key});

  @override
  State<MyLocationsScreen> createState() => _MyLocationsScreenState();
}

class _MyLocationsScreenState extends State<MyLocationsScreen> {
  Map<String, UserLocation> _locations = {};
  bool _loading = true;

  final _labels = <String, String>{
    'home': 'Home',
    'gym': 'Gym',
    'work': 'Work',
    'school': 'School / University',
  };

  final _icons = <String, IconData>{
    'home': Icons.home_rounded,
    'gym': Icons.fitness_center_rounded,
    'work': Icons.work_outline_rounded,
    'school': Icons.school_rounded,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  // تحميل المواقع المحفوظة من Firestore عند فتح الشاشة.
  Future<void> _load() async {
    final locs = await UserLocationsService.getLocations();
    if (mounted) {
      setState(() {
        _locations = locs;
        _loading = false;
      });
    }
  }

  // حفظ نوع موقع باستخدام إحداثيات GPS الحالية وعنوانها العكسي.
  Future<void> _saveWithCurrentLocation(String type) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      final name = _locations[type]?.name ?? _labels[type] ?? type;
      final place = await NominatimService.reverse(pos.latitude, pos.longitude);
      await UserLocationsService.saveLocation(
        type,
        name: name,
        lat: pos.latitude,
        lng: pos.longitude,
        address: place?.displayName,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_labels[type]} location saved'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // فتح حوار لتعديل اسم الموقع (مثلاً نادي ابن خلدون بدلاً من "النادي").
  Future<void> _editName(String type) async {
    final current = _locations[type]?.name ?? '';
    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${_labels[type]} name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. My Gym, Office'),
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

    if (newName == null) return;
    final loc = _locations[type];
    await UserLocationsService.saveLocation(
      type,
      name: newName.isEmpty ? (_labels[type] ?? type) : newName,
      lat: loc?.lat,
      lng: loc?.lng,
      address: loc?.address,
    );
    await _load();
  }

  // مسح موقع شخصي بعد تأكيد المستخدم.
  Future<void> _clear(String type) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear ${_labels[type]}?'),
        content: const Text('This will remove the saved location.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await UserLocationsService.saveLocation(type, name: null, lat: null, lng: null);
    await _load();
  }

  // فتح شاشة اختيار الموقع من الخريطة وحفظ النتيجة.
  Future<void> _pickOnMap(String type) async {
    final result = await Navigator.push<LocationPickerResult>(
      context,
      MaterialPageRoute(
        builder: (ctx) => LocationPickerScreen(
          title: 'Set ${_labels[type]}',
          initialLat: _locations[type]?.lat,
          initialLng: _locations[type]?.lng,
        ),
      ),
    );

    if (result == null) return;

    final name = _locations[type]?.name ?? _labels[type] ?? type;
    await UserLocationsService.saveLocation(
      type,
      name: name,
      lat: result.lat,
      lng: result.lng,
      address: result.address,
    );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_labels[type]} location saved'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Locations')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _labels.entries.map((e) {
                final type = e.key;
                final label = e.value;
                final loc = _locations[type];
                final isSet = loc != null && loc.isSet;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.1),
                              child: Icon(
                                _icons[type] ?? Icons.place,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (loc != null && loc.name != null && loc.name!.isNotEmpty && loc.name != label)
                                        ? loc.name!
                                        : label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (loc != null && loc.isSet)
                                    Text(
                                      loc.address ?? 'Tap to set location',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: loc.address != null
                                            ? AppColors.textSecondary
                                            : AppColors.textSecondary.withValues(alpha: 0.5),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  else
                                    const Text(
                                      'Not set yet',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (loc != null && loc.isSet)
                              IconButton(
                                icon: const Icon(Icons.edit_location_alt_outlined,
                                    color: AppColors.textSecondary),
                                onPressed: () => _editName(type),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _pickOnMap(type),
                            icon: const Icon(Icons.map_outlined, size: 18),
                            label: Text(isSet ? 'Change on Map' : 'Pick on Map'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _saveWithCurrentLocation(type),
                            icon: const Icon(Icons.my_location, size: 18),
                            label: const Text('Use Current Location'),
                          ),
                        ),
                        if (isSet) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => _clear(type),
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                            label: const Text('Clear Location', style: TextStyle(color: AppColors.error)),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}
