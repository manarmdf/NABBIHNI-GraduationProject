import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../shared/constants.dart';
import 'nominatim_service.dart';

// نتيجة شاشة اختيار الموقع: الإحداثيات والعنوان النصي.
class LocationPickerResult {
  final double lat;
  final double lng;
  final String? address;

  LocationPickerResult({
    required this.lat,
    required this.lng,
    this.address,
  });
}

// شاشة اختيار موقع تتيح 3 طرق:
// 1) إدخال إحداثيات يدوياً.
// 2) البحث بالاسم عبر Nominatim المجاني.
// 3) النقر على الخريطة لوضع المؤشر.
class LocationPickerScreen extends StatefulWidget {
  final String title;
  final double? initialLat;
  final double? initialLng;

  const LocationPickerScreen({
    super.key,
    this.title = 'Pick Location',
    this.initialLat,
    this.initialLng,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late TextEditingController _searchController;

  LatLng? _selectedPosition;
  String? _selectedAddress;
  bool _loadingAddress = false;
  bool _searching = false;
  bool _noResults = false;
  List<NominatimPlace> _searchResults = [];
  Timer? _debounceTimer;
  final FocusNode _searchFocusNode = FocusNode();

  GoogleMapController? _mapController;
  final Map<MarkerId, Marker> _markers = {};
  bool _isMovingMap = false;
  LatLng? _cameraCenter;

  @override
  void initState() {
    super.initState();
    _latController = TextEditingController();
    _lngController = TextEditingController();
    _searchController = TextEditingController();

    if (widget.initialLat != null && widget.initialLng != null) {
      _selectedPosition = LatLng(widget.initialLat!, widget.initialLng!);
      _latController.text = widget.initialLat!.toString();
      _lngController.text = widget.initialLng!.toString();
      _updateMarker();
      _fetchAddress();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _latController.dispose();
    _lngController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // إعادة بناء العلامة على الخريطة عند تغيير الموقع المحدد.
  void _updateMarker() {
    if (_selectedPosition == null) return;

    final markerId = const MarkerId('selected');
    _markers[markerId] = Marker(
      markerId: markerId,
      position: _selectedPosition!,
      draggable: true,
      onDragEnd: (pos) {
        setState(() {
          _selectedPosition = pos;
          _latController.text = pos.latitude.toStringAsFixed(6);
          _lngController.text = pos.longitude.toStringAsFixed(6);
        });
        _fetchAddress();
      },
    );
  }

  // جلب العنوان النصي للموقع المحدد عبر الترميز العكسي.
  Future<void> _fetchAddress() async {
    if (_selectedPosition == null) return;

    setState(() => _loadingAddress = true);

    final place = await NominatimService.reverse(
      _selectedPosition!.latitude,
      _selectedPosition!.longitude,
    );

    if (mounted) {
      setState(() {
        _loadingAddress = false;
        _selectedAddress = place?.displayName;
      });
    }
  }

  // عند النقر على الخريطة: تحديث الإحداثيات وجلب العنوان.
  void _onMapTap(LatLng pos) {
    setState(() {
      _selectedPosition = pos;
      _latController.text = pos.latitude.toStringAsFixed(6);
      _lngController.text = pos.longitude.toStringAsFixed(6);
      _selectedAddress = null;
    });
    _updateMarker();
    _fetchAddress();
  }

  // تطبيق إحداثيات الإدخال اليدوي بعد التحقق من صحة المدى.
  void _applyManualInput() {
    final lat = double.tryParse(_latController.text);
    final lng = double.tryParse(_lngController.text);

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid numbers for latitude and longitude'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Latitude must be -90 to 90, Longitude must be -180 to 180'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _selectedPosition = LatLng(lat, lng);
      _selectedAddress = null;
    });
    _updateMarker();
    _fetchAddress();
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(_selectedPosition!),
    );
  }

  // البحث مع تأخير: ينتظر 500 ميلي ثانية بعد توقف المستخدم عن الكتابة.
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _noResults = false;
      });
      return;
    }

    setState(() {
      _searching = true;
      _noResults = false;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _search(query.trim());
    });
  }

  // استخراج الاسم الرئيسي للمكان (الجزء قبل أول فاصلة).
  String _extractMainName(String? displayName) {
    if (displayName == null || displayName.isEmpty) return 'Unknown place';
    final parts = displayName.split(',');
    return parts.first.trim();
  }

  // استخراج باقي العنوان (كل ما بعد أول فاصلة).
  String _extractAddress(String? displayName) {
    if (displayName == null || displayName.isEmpty) return '';
    final parts = displayName.split(',');
    if (parts.length <= 1) return '';
    return parts.skip(1).join(',').trim();
  }

  // تنفيذ بحث Nominatim الفعلي وعرض النتائج في القائمة المنسدلة.
  Future<void> _search(String query) async {
    if (query.isEmpty) return;

    final results = await NominatimService.search(query);

    if (mounted) {
      setState(() {
        _searching = false;
        _searchResults = results;
        _noResults = results.isEmpty;
      });
    }
  }

  // اختيار نتيجة بحث وتحريك الخريطة إليها.
  void _selectSearchResult(NominatimPlace place) {
    setState(() {
      _selectedPosition = LatLng(place.lat, place.lng);
      _latController.text = place.lat.toStringAsFixed(6);
      _lngController.text = place.lng.toStringAsFixed(6);
      _selectedAddress = place.displayName;
      _searchResults = [];
      _searchController.clear();
    });
    _updateMarker();
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_selectedPosition!, 16),
    );
  }

  // الانتقال للموقع الحالي للجهاز عبر GPS.
  Future<void> _goToCurrentLocation() async {
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      setState(() {
        _selectedPosition = LatLng(pos.latitude, pos.longitude);
        _latController.text = pos.latitude.toStringAsFixed(6);
        _lngController.text = pos.longitude.toStringAsFixed(6);
        _selectedAddress = null;
      });
      _updateMarker();
      _fetchAddress();
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_selectedPosition!, 16),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    }
  }

  // تأكيد الاختيار وإرجاع النتيجة للشاشة السابقة.
  void _confirm() {
    if (_selectedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location first'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      LocationPickerResult(
        lat: _selectedPosition!.latitude,
        lng: _selectedPosition!.longitude,
        address: _selectedAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    // تصغير القائمة المنسدلة عند ظهور لوحة المفاتيح.
    final dropdownMax = keyboardInset > 0 ? 180.0 : 250.0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: _selectedPosition != null ? _confirm : null,
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search for a place...',
                    prefixIcon: _searching 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _debounceTimer?.cancel();
                              setState(() {
                                _searchResults = [];
                                _searching = false;
                                _noResults = false;
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: AppColors.background,
                  ),
                  onChanged: _onSearchChanged,
                ),
                if (_searchResults.isNotEmpty || _searching || _noResults)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: BoxConstraints(maxHeight: dropdownMax),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _searching && _searchResults.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Searching...',
                                    style: TextStyle(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _noResults
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.search_off, color: AppColors.textSecondary, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'No results found',
                                        style: TextStyle(color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: Colors.grey.shade200,
                            ),
                            itemBuilder: (ctx, i) {
                              final place = _searchResults[i];
                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.place, color: AppColors.primary, size: 20),
                                ),
                                title: Text(
                                  _extractMainName(place.displayName),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  _extractAddress(place.displayName),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                onTap: () => _selectSearchResult(place),
                              );
                            },
                          ),
                  ),
              ],
            ),
              ),
            ),
          ),

          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _selectedPosition ?? const LatLng(24.7136, 46.6753),
                    zoom: _selectedPosition != null ? 15 : 10,
                  ),
                  onMapCreated: (ctrl) => _mapController = ctrl,
                  onTap: _onMapTap,
                  onCameraMove: (position) {
                    _cameraCenter = position.target;
                    if (!_isMovingMap) {
                      setState(() => _isMovingMap = true);
                    }
                  },
                  onCameraIdle: () {
                    if (_isMovingMap && _cameraCenter != null) {
                      setState(() {
                        _isMovingMap = false;
                        _selectedPosition = _cameraCenter;
                        _latController.text = _cameraCenter!.latitude.toStringAsFixed(6);
                        _lngController.text = _cameraCenter!.longitude.toStringAsFixed(6);
                        _selectedAddress = null;
                      });
                      _updateMarker();
                      _fetchAddress();
                    }
                  },
                  markers: _markers.values.toSet(),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 36),
                    child: Icon(
                      Icons.location_pin,
                      size: 42,
                      color: _isMovingMap
                          ? AppColors.primary.withValues(alpha: 0.5)
                          : AppColors.primary,
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'myLocation',
                    onPressed: _goToCurrentLocation,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.my_location, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _latController,
                        decoration: InputDecoration(
                          labelText: 'Latitude',
                          hintText: 'e.g. 24.7136',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _lngController,
                        decoration: InputDecoration(
                          labelText: 'Longitude',
                          hintText: 'e.g. 46.6753',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _applyManualInput,
                      icon: const Icon(Icons.check),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),

                if (_selectedPosition != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _loadingAddress
                            ? const Text(
                                'Loading address...',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            : Text(
                                _selectedAddress ??
                                    '${_selectedPosition!.latitude.toStringAsFixed(5)}, ${_selectedPosition!.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _goToCurrentLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use Current Location'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
