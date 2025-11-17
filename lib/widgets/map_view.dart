import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// Lightweight model for facilities rendered on the map.
class FacilityPin {
  final String id;
  final String name;
  final String type; // 'hospital', 'clinic', 'police', 'firestation', etc.
  final double lon;
  final double lat;
  final Map<String, dynamic>? meta;
  final String source; // 'manual' or 'google_places'

  const FacilityPin({
    required this.id,
    required this.name,
    required this.type,
    required this.lon,
    required this.lat,
    this.meta,
    this.source = 'manual',
  });

  /// Create a FacilityPin from a Google Places facility
  factory FacilityPin.fromGooglePlace(dynamic googlePlace) {
    return FacilityPin(
      id: googlePlace.placeId,
      name: googlePlace.name,
      type: googlePlace.category,
      lon: googlePlace.lng,
      lat: googlePlace.lat,
      source: 'google_places',
      meta: {
        'address': googlePlace.address,
        'rating': googlePlace.rating,
        'isOpenNow': googlePlace.isOpenNow,
        'userRatingsTotal': googlePlace.userRatingsTotal,
        'placeId': googlePlace.placeId,
      },
    );
  }
}

/// Model for emergency alerts shown on the map
class EmergencyAlert {
  final String id;
  final String userId;
  final String userEmail;
  final double lon;
  final double lat;
  final List<String> services;
  final String description;
  final String status;
  final DateTime? createdAt;

  const EmergencyAlert({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.lon,
    required this.lat,
    required this.services,
    required this.description,
    required this.status,
    this.createdAt,
  });
}

/// Controller to expose imperative actions from MapView to parent widgets.
class MapViewController {
  VoidCallback? _clearTempPin;
  VoidCallback? _recenterOnUser;

  void clearTempPin() => _clearTempPin?.call();
  void recenterOnUserLocation() => _recenterOnUser?.call();

  // Setters for internal use
  set clearTempPinCallback(VoidCallback? callback) {
    _clearTempPin = callback;
  }

  set recenterOnUserLocationCallback(VoidCallback? callback) {
    _recenterOnUser = callback;
  }
}

class MapView extends StatefulWidget {
  const MapView({
    super.key,
    this.enableTap = false,
    this.onMapTap,
    this.controller,
    this.facilities,
    this.onFacilityTap,
    this.emergencyAlerts,
    this.onEmergencyAlertTap,
    this.followUserLocation = true,
    this.routePolyline,
  });

  /// When true, a tap places a temporary pin and calls [onMapTap].
  final bool enableTap;
  final void Function(double lon, double lat)? onMapTap;

  /// Controller to clear temp pin, etc.
  final MapViewController? controller;

  /// Facilities to render as persistent pins.
  final List<FacilityPin>? facilities;

  /// Called when a facility pin is tapped.
  final ValueChanged<FacilityPin>? onFacilityTap;

  /// Emergency alerts to render as black pins.
  final List<EmergencyAlert>? emergencyAlerts;

  /// Called when an emergency alert pin is tapped.
  final ValueChanged<EmergencyAlert>? onEmergencyAlertTap;

  /// When true, camera automatically follows user location. When false, user can freely pan.
  final bool followUserLocation;

  /// Route polyline to display on map
  final Polyline? routePolyline;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  GoogleMapController? _mapController;

  // Subscriptions
  StreamSubscription<geo.Position>? _positionStream;
  Timer? _interpolationTimer;

  // Markers and tracking
  final Map<String, Marker> _markers = {};
  LatLng? _userPosition;
  LatLng? _tempPinPosition;

  // Custom marker icons
  BitmapDescriptor? _userLocationIcon;
  BitmapDescriptor? _sosAlertIcon;

  // Facility marker icons by type
  final Map<String, BitmapDescriptor> _facilityIcons = {};

  // Smooth interpolation between GPS updates
  LatLng? _currentDisplayPosition;
  LatLng? _targetPosition;
  DateTime? _interpolationStartTime;
  static const _interpolationDuration = Duration(milliseconds: 800);

  // Convenience getters
  List<FacilityPin> get _facilities =>
      widget.facilities ?? const <FacilityPin>[];
  List<EmergencyAlert> get _emergencyAlerts =>
      widget.emergencyAlerts ?? const <EmergencyAlert>[];

  @override
  void initState() {
    super.initState();
    widget.controller?.clearTempPinCallback = _clearTempPinInternal;
    widget.controller?.recenterOnUserLocationCallback =
        _recenterOnUserLocationInternal;
    _createCustomMarkers();
    _startLocationTracking();
  }

  /// Create custom circular markers for user location and SOS alerts
  Future<void> _createCustomMarkers() async {
    try {
      // Create custom circular markers for all platforms
      // Much smaller size for GPS-like appearance
      final size = kIsWeb ? 24.0 : 28.0;
      print(
        'Creating circular markers (size: $size, platform: ${kIsWeb ? 'web' : 'native'})',
      );

      _userLocationIcon = await _createCircularMarker(
        color: const Color(0xFF4285F4), // Google Maps blue
        size: size,
        borderColor: Colors.white,
        borderWidth: 2.5,
      );
      print('User location icon created');

      _sosAlertIcon = await _createCircularMarker(
        color: const Color(0xFFEA4335), // Red for emergency
        size: size,
        borderColor: Colors.white,
        borderWidth: 2.5,
      );
      print('SOS alert icon created');

      // Create facility markers (only for web, native uses defaultMarkerWithHue)
      if (kIsWeb) {
        print('Creating custom facility markers for web');
        _facilityIcons['hospital'] = await _createPinMarker(
          color: const Color(0xFFEA4335), // Red
        );
        _facilityIcons['clinic'] = await _createPinMarker(
          color: const Color(0xFFFF69B4), // Pink
        );
        _facilityIcons['police station'] = await _createPinMarker(
          color: const Color(0xFF4285F4), // Blue
        );
        _facilityIcons['fire station'] = await _createPinMarker(
          color: const Color(0xFFFF8C00), // Orange
        );
        _facilityIcons['default'] = await _createPinMarker(
          color: const Color(0xFF34A853), // Green
        );
        print('Facility markers created');
      }

      if (mounted) {
        _updateMarkers();
      }
    } catch (e) {
      print('Error creating custom markers: $e');
      // Fallback to default markers if custom creation fails
      _userLocationIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueAzure,
      );
      _sosAlertIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueRed,
      );
      if (mounted) {
        _updateMarkers();
      }
    }
  }

  /// Generate a circular marker icon
  Future<BitmapDescriptor> _createCircularMarker({
    required Color color,
    required double size,
    Color borderColor = Colors.white,
    double borderWidth = 3,
  }) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);

    // Fill background with transparency
    final backgroundPaint = Paint()..color = Colors.transparent;
    canvas.drawRect(Rect.fromLTWH(0, 0, size, size), backgroundPaint);

    final radius = size / 2;
    final center = Offset(radius, radius);

    // Draw white border (outer circle)
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius, borderPaint);

    // Draw filled circle (inner circle)
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius - borderWidth, fillPaint);

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    if (bytes == null) {
      throw Exception('Failed to create marker image');
    }

    return BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
  }

  /// Generate a pin/teardrop-shaped marker icon for facilities
  Future<BitmapDescriptor> _createPinMarker({
    required Color color,
    double size = 48,
  }) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);

    // Create a path for the pin shape
    final path = Path();
    final centerX = size / 2;
    final topY = 0.0;
    final circleRadius = size * 0.35;
    final pointY = size;

    // Draw the teardrop/pin shape
    // Top circle
    path.addOval(
      Rect.fromCircle(
        center: Offset(centerX, topY + circleRadius),
        radius: circleRadius,
      ),
    );

    // Triangle pointing down
    path.moveTo(centerX - circleRadius * 0.7, topY + circleRadius * 1.5);
    path.lineTo(centerX, pointY);
    path.lineTo(centerX + circleRadius * 0.7, topY + circleRadius * 1.5);
    path.close();

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..isAntiAlias = true;
    canvas.drawPath(path, shadowPaint);

    // Draw white border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..isAntiAlias = true;
    canvas.drawPath(path, borderPaint);

    // Draw filled pin
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, fillPaint);

    // Draw center dot
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(
      Offset(centerX, topY + circleRadius),
      circleRadius * 0.3,
      dotPaint,
    );

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(size.toInt(), (size * 1.2).toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    if (bytes == null) {
      throw Exception('Failed to create pin marker image');
    }

    return BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      widget.controller?.clearTempPinCallback = _clearTempPinInternal;
      widget.controller?.recenterOnUserLocationCallback =
          _recenterOnUserLocationInternal;
    }
    // Redraw when facilities or alerts list changes
    if (oldWidget.facilities != widget.facilities ||
        oldWidget.emergencyAlerts != widget.emergencyAlerts) {
      _updateMarkers();
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _interpolationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _applyMapStyle();
    _updateMarkers();
  }

  /// Apply custom map style to hide non-emergency POI labels
  void _applyMapStyle() async {
    // Web needs longer delays for map style to apply properly
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    try {
      await _mapController?.setMapStyle(_mapStyleJson);
      print('Map style applied - hiding non-emergency POI labels');

      // On web, apply multiple times to ensure it sticks
      if (kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 1000));
        await _mapController?.setMapStyle(_mapStyleJson);
        print('Map style reapplied for web');

        // Third time for good measure on web
        await Future.delayed(const Duration(milliseconds: 1000));
        await _mapController?.setMapStyle(_mapStyleJson);
        print('Map style applied third time for web');
      }
    } catch (e) {
      print('Error applying map style: $e');
    }
  }

  void _onMapTapped(LatLng position) {
    if (widget.enableTap && widget.onMapTap != null) {
      setState(() {
        _tempPinPosition = position;
      });
      _updateMarkers();
      widget.onMapTap?.call(position.longitude, position.latitude);
    }
  }

  void _clearTempPinInternal() {
    setState(() {
      _tempPinPosition = null;
    });
    _updateMarkers();
  }

  void _recenterOnUserLocationInternal() {
    if (_userPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _userPosition!, zoom: 15.0),
        ),
      );
    }
  }

  /// Start location tracking with smooth interpolation
  void _startLocationTracking() async {
    try {
      final permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        await geo.Geolocator.requestPermission();
      }

      try {
        final current = await geo.Geolocator.getCurrentPosition();
        final initialPos = LatLng(current.latitude, current.longitude);
        _startInterpolationTo(initialPos);

        _positionStream =
            geo.Geolocator.getPositionStream(
              locationSettings: const geo.LocationSettings(
                accuracy: geo.LocationAccuracy.high,
                distanceFilter: 1,
              ),
            ).listen((geo.Position pos) {
              final newPos = LatLng(pos.latitude, pos.longitude);
              _startInterpolationTo(newPos);
            });
      } catch (e) {
        // Fallback to default location (KL) if location fails
        _useMockLocation();
      }
    } catch (e) {
      _useMockLocation();
    }
  }

  void _useMockLocation() {
    final mockPos = LatLng(3.1390, 101.6869); // Kuala Lumpur
    setState(() {
      _userPosition = mockPos;
      _currentDisplayPosition = mockPos;
    });
    // Only animate camera if followUserLocation is enabled
    if (widget.followUserLocation) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: mockPos, zoom: 13.0),
        ),
      );
    }
    _updateMarkers();
  }

  /// Ease-out-cubic easing function
  double _easeOutCubic(double t) {
    return 1.0 - math.pow(1.0 - t, 3.0);
  }

  /// Linear interpolation between two positions with easing
  LatLng _lerpPosition(LatLng start, LatLng end, double t) {
    t = t.clamp(0.0, 1.0);
    final easedT = _easeOutCubic(t);
    return LatLng(
      start.latitude + (end.latitude - start.latitude) * easedT,
      start.longitude + (end.longitude - start.longitude) * easedT,
    );
  }

  void _updateInterpolation() {
    if (_currentDisplayPosition == null ||
        _targetPosition == null ||
        _interpolationStartTime == null) {
      return;
    }

    final elapsed = DateTime.now().difference(_interpolationStartTime!);
    final progress =
        (elapsed.inMilliseconds / _interpolationDuration.inMilliseconds).clamp(
          0.0,
          1.0,
        );

    final newPosition = _lerpPosition(
      _currentDisplayPosition!,
      _targetPosition!,
      progress,
    );

    setState(() {
      _userPosition = newPosition;
      _currentDisplayPosition = newPosition;
    });

    // Only animate camera if followUserLocation is enabled
    if (widget.followUserLocation) {
      _mapController?.animateCamera(CameraUpdate.newLatLng(newPosition));
    }
    _updateMarkers();

    if (progress >= 1.0) {
      _interpolationTimer?.cancel();
      _interpolationTimer = null;
    }
  }

  void _startInterpolationTo(LatLng newTarget) {
    if (_currentDisplayPosition == null) {
      setState(() {
        _currentDisplayPosition = newTarget;
        _targetPosition = newTarget;
        _userPosition = newTarget;
      });
      // Only animate camera on initial position if followUserLocation is enabled
      if (widget.followUserLocation) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: newTarget, zoom: 15.0),
          ),
        );
      }
      _updateMarkers();
      return;
    }

    _targetPosition = newTarget;
    _interpolationStartTime = DateTime.now();
    _interpolationTimer?.cancel();

    _interpolationTimer = Timer.periodic(
      const Duration(milliseconds: 16), // ~60 FPS
      (_) {
        if (mounted) {
          _updateInterpolation();
        }
      },
    );
  }

  /// Update all markers on the map
  void _updateMarkers() {
    final markers = <String, Marker>{};

    // User position marker (blue circular dot)
    if (_userPosition != null && _userLocationIcon != null) {
      markers['user'] = Marker(
        markerId: const MarkerId('user'),
        position: _userPosition!,
        icon: _userLocationIcon!,
        anchor: const Offset(0.5, 0.5), // Center the circular marker
        zIndex: 100,
      );
    }

    // Facility markers
    for (final facility in _facilities) {
      BitmapDescriptor icon;
      if (kIsWeb) {
        // Use custom markers on web
        final type = facility.type.toLowerCase().trim();
        icon =
            _facilityIcons[type] ??
            _facilityIcons['default'] ??
            BitmapDescriptor.defaultMarker;
      } else {
        // Use hue-based markers on native
        icon = BitmapDescriptor.defaultMarkerWithHue(
          _hueForType(facility.type),
        );
      }

      markers[facility.id] = Marker(
        markerId: MarkerId(facility.id),
        position: LatLng(facility.lat, facility.lon),
        icon: icon,
        infoWindow: InfoWindow(title: facility.name, snippet: facility.type),
        onTap: () => widget.onFacilityTap?.call(facility),
        zIndex: 50,
      );
    }

    // Emergency alert markers (red circular dots)
    if (_sosAlertIcon != null) {
      for (final alert in _emergencyAlerts) {
        markers[alert.id] = Marker(
          markerId: MarkerId(alert.id),
          position: LatLng(alert.lat, alert.lon),
          icon: _sosAlertIcon!,
          anchor: const Offset(0.5, 0.5), // Center the circular marker
          infoWindow: InfoWindow(
            title: 'Emergency Alert',
            snippet: alert.description,
          ),
          onTap: () => widget.onEmergencyAlertTap?.call(alert),
          zIndex: 75,
        );
      }
    }

    // Temp pin marker (red pin)
    if (_tempPinPosition != null) {
      markers['temp_pin'] = Marker(
        markerId: const MarkerId('temp_pin'),
        position: _tempPinPosition!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'New Location'),
        zIndex: 90,
      );
    }

    setState(() {
      _markers.clear();
      _markers.addAll(markers);
    });
  }

  /// Get marker hue based on facility type
  double _hueForType(String type) {
    final t = type.toLowerCase().trim();
    if (t == 'hospital') return BitmapDescriptor.hueRed;
    if (t == 'clinic') return BitmapDescriptor.hueRose;
    if (t == 'police station') return BitmapDescriptor.hueAzure;
    if (t == 'fire station' || t == 'fire') return BitmapDescriptor.hueOrange;
    return BitmapDescriptor.hueGreen;
  }

  // Map style to hide labels for non-emergency POIs but keep emergency services visible
  static const String _mapStyleJson = '''
[
  {
    "featureType": "poi",
    "elementType": "labels",
    "stylers": [{"visibility": "off"}]
  },
  {
    "featureType": "poi.medical",
    "elementType": "labels",
    "stylers": [{"visibility": "on"}]
  },
  {
    "featureType": "poi.government",
    "elementType": "labels",
    "stylers": [{"visibility": "on"}]
  },
  {
    "featureType": "transit",
    "elementType": "labels",
    "stylers": [{"visibility": "off"}]
  }
]
''';

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: const CameraPosition(
            target: LatLng(3.1390, 101.6869), // KL default
            zoom: 13.0,
          ),
          markers: _markers.values.toSet(),
          polylines: widget.routePolyline != null
              ? {widget.routePolyline!}
              : {},
          myLocationEnabled: false, // We handle user location ourselves
          myLocationButtonEnabled: false,
          mapToolbarEnabled: true,
          zoomControlsEnabled: true,
          onTap: _onMapTapped,
          mapType: MapType.normal,
        ),

        // Debug HUD
        Positioned(
          left: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'pins: ${_facilities.length} | alerts: ${_emergencyAlerts.length}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
