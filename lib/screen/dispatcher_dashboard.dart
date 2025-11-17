import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/map_view.dart';
import '../places_service.dart';
import '../directions_service.dart';
import 'add_facility_screen.dart';

class DispatcherDashboard extends StatefulWidget {
  const DispatcherDashboard({super.key});

  @override
  State<DispatcherDashboard> createState() => _DispatcherDashboardState();
}

class _DispatcherDashboardState extends State<DispatcherDashboard> {
  double? _pendingLon;
  double? _pendingLat;

  // Add Mode toggle: when true, MapView captures the next tap for temp pin
  bool _addMode = false;

  // Controller to clear the temporary pin on Cancel/Add
  final _mapController = MapViewController();

  // User location and Google Places facilities
  Position? _userLocation;
  List<FacilityPin> _googlePlacesPins = [];
  bool _loadingGooglePlaces = false;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Route navigation
  Polyline? _currentRoute;
  RouteInfo? _currentRouteInfo;
  double? _destinationLat;
  double? _destinationLon;
  Position? _lastRouteUpdatePosition;

  // Search radius in meters (5km)
  static const int _searchRadiusMeters = 5000;

  // Route tracking thresholds
  static const double _offRouteThresholdMeters = 50.0; // How far off route before recalculating
  static const double _minDistanceForRouteUpdateMeters = 20.0; // Min distance moved before checking route

  // Minimum distance (in meters) user must move before refreshing facilities
  static const double _refreshDistanceThreshold = 500.0;

  @override
  void initState() {
    super.initState();
    _fetchUserLocationAndGooglePlaces();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  void _startLocationTracking() {
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters for better route tracking
      ),
    ).listen((Position newPosition) {
      if (!mounted) return;

      // Check if user has moved far enough to warrant refreshing facilities
      if (_userLocation != null) {
        final distance = PlacesService.calculateDistance(
          _userLocation!.latitude,
          _userLocation!.longitude,
          newPosition.latitude,
          newPosition.longitude,
        );

        // Only refresh if moved more than threshold
        if (distance >= _refreshDistanceThreshold) {
          _userLocation = newPosition;
          _refreshFacilities(newPosition);
        }

        // Update route if we have an active route
        if (_currentRoute != null && _destinationLat != null && _destinationLon != null) {
          _updateRouteProgress(newPosition);
        }
      } else {
        _userLocation = newPosition;
      }

      _userLocation = newPosition;
    });
  }

  Future<void> _refreshFacilities(Position position) async {
    if (_loadingGooglePlaces) return; // Don't refresh if already loading

    try {
      // Fetch Google Places facilities within the specified radius
      final googleFacilities = await PlacesService.getAllEmergencyFacilities(
        position.latitude,
        position.longitude,
        radiusMeters: _searchRadiusMeters,
      );

      // Convert to FacilityPin
      final pins = googleFacilities
          .map((gf) => FacilityPin.fromGooglePlace(gf))
          .toList();

      if (mounted) {
        setState(() {
          _googlePlacesPins = pins;
        });
      }
    } catch (e) {
      // Silently fail for background updates
      print('Error refreshing facilities: $e');
    }
  }

  Future<void> _fetchUserLocationAndGooglePlaces() async {
    setState(() => _loadingGooglePlaces = true);

    Position? position;

    try {
      // Check and request location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        try {
          // Get current location
          position = await Geolocator.getCurrentPosition();
          _userLocation = position;
        } catch (e) {
          print('Error getting location: $e');
          // Fall through to use mock location
        }
      }
    } catch (e) {
      print('Error checking permission: $e');
      // Fall through to use mock location
    }

    // If we don't have a position, use mock location (Kuala Lumpur)
    if (position == null) {
      print('Using mock location (Kuala Lumpur)');
      // Use mock position for KL
      position = Position(
        latitude: 3.1390,
        longitude: 101.6869,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      _userLocation = position;
    }

    try {
      // Fetch Google Places facilities within the specified radius
      final googleFacilities = await PlacesService.getAllEmergencyFacilities(
        position.latitude,
        position.longitude,
        radiusMeters: _searchRadiusMeters,
      );

      print('Fetched ${googleFacilities.length} Google Places facilities');

      // Convert to FacilityPin
      final pins = googleFacilities
          .map((gf) => FacilityPin.fromGooglePlace(gf))
          .toList();

      if (mounted) {
        setState(() {
          _googlePlacesPins = pins;
          _loadingGooglePlaces = false;
        });
      }
    } catch (e) {
      print('Error fetching Google Places: $e');
      if (mounted) {
        setState(() => _loadingGooglePlaces = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load Google Places: $e')),
        );
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Logout failed: $e")));
    }
  }

  void _armAddMode() {
    setState(() => _addMode = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Add Mode enabled — tap the map to choose a location."),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _disarmAddMode({bool showSnack = false}) {
    setState(() {
      _addMode = false;
      _pendingLat = null;
      _pendingLon = null;
    });
    if (showSnack) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Add Mode disabled.")));
    }
  }

  void _handleMapTap(double lon, double lat) {
    _pendingLon = lon;
    _pendingLat = lat;

    showModalBottomSheet(
      context: context,
      builder: (_) => _AddHereSheet(
        lon: lon,
        lat: lat,
        onAdd: () async {
          if (!mounted) return;
          Navigator.pop(context); // close sheet

          // Go to Add Facility form with preset coords.
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddFacilityScreen(presetLat: lat, presetLon: lon),
            ),
          );

          // Clear temp pin & disarm after returning
          _mapController.clearTempPin();
          _disarmAddMode();
        },
        onCancel: () {
          Navigator.pop(context);
          _mapController.clearTempPin(); // remove red temp pin
          _disarmAddMode(showSnack: true);
        },
      ),
    );
  }

  void _handleFacilityTap(FacilityPin f) {
    // Show details for the saved facility
    showModalBottomSheet(
      context: context,
      builder: (_) => _FacilityDetailsSheet(facility: f),
    );
  }

  void _handleEmergencyAlertTap(EmergencyAlert alert) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _EmergencyAlertSheet(
        alert: alert,
        userLocation: _userLocation,
        onNavigate: () => _navigateToAlert(alert),
      ),
    );
  }

  Future<void> _navigateToAlert(EmergencyAlert alert) async {
    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to get your location'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Clear any existing route FIRST and wait for UI to update
    setState(() {
      _currentRoute = null;
      _currentRouteInfo = null;
    });

    // Wait a frame to ensure the polyline is cleared from the map
    await Future.delayed(const Duration(milliseconds: 100));

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 16),
            Text('Calculating route...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    print('===== ROUTE CALCULATION START =====');
    print('Origin: ${_userLocation!.latitude}, ${_userLocation!.longitude}');
    print('Destination: ${alert.lat}, ${alert.lon}');

    final route = await DirectionsService.getRoute(
      originLat: _userLocation!.latitude,
      originLng: _userLocation!.longitude,
      destLat: alert.lat,
      destLng: alert.lon,
    );

    if (route == null) {
      print('ERROR: DirectionsService returned null');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to calculate route'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('Route calculation successful');
    print('Points count: ${route.polylinePoints.length}');

    // Validate we have enough points (should be more than 2 for a real route)
    if (route.polylinePoints.isEmpty) {
      print('ERROR: No polyline points received!');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route calculation returned no points'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (route.polylinePoints.length < 3) {
      print('WARNING: Only ${route.polylinePoints.length} points - this will be a straight line!');
    }

    // Show first, middle, and last points
    print('First point: ${route.polylinePoints.first.latitude}, ${route.polylinePoints.first.longitude}');
    if (route.polylinePoints.length > 2) {
      final midIndex = route.polylinePoints.length ~/ 2;
      print('Middle point: ${route.polylinePoints[midIndex].latitude}, ${route.polylinePoints[midIndex].longitude}');
    }
    print('Last point: ${route.polylinePoints.last.latitude}, ${route.polylinePoints.last.longitude}');

    // Validate all coordinates are reasonable
    for (int i = 0; i < route.polylinePoints.length; i++) {
      final point = route.polylinePoints[i];
      if (point.latitude < -90 || point.latitude > 90 ||
          point.longitude < -180 || point.longitude > 180) {
        print('ERROR: Invalid coordinate at index $i: ${point.latitude}, ${point.longitude}');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid route coordinates received'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    print('All coordinates validated successfully');
    print('Creating polyline with unique ID: route_${DateTime.now().millisecondsSinceEpoch}');

    setState(() {
      _currentRouteInfo = route;
      _destinationLat = alert.lat;
      _destinationLon = alert.lon;
      _lastRouteUpdatePosition = _userLocation;
      // Use unique polylineId to force re-render
      // Note: geodesic doesn't work well on web, but the detailed polyline points should be sufficient
      _currentRoute = Polyline(
        polylineId: PolylineId('route_${DateTime.now().millisecondsSinceEpoch}'),
        points: route.polylinePoints,
        color: Colors.blue,
        width: kIsWeb ? 6 : 5,
        geodesic: !kIsWeb, // Only use geodesic on native platforms
        visible: true,
      );
    });

    print('Polyline created and set in state');
    print('===== ROUTE CALCULATION END =====');

    // Close the bottom sheet
    Navigator.pop(context);

    // Show route info
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Route: ${route.distance} (${route.polylinePoints.length} points), ETA: ${route.duration}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Clear',
          textColor: Colors.white,
          onPressed: _clearRoute,
        ),
      ),
    );
  }

  void _clearRoute() {
    setState(() {
      _currentRoute = null;
      _currentRouteInfo = null;
      _destinationLat = null;
      _destinationLon = null;
      _lastRouteUpdatePosition = null;
    });
  }

  /// Update route based on user's current position
  Future<void> _updateRouteProgress(Position currentPosition) async {
    if (_currentRoute == null || _currentRouteInfo == null) return;
    if (_destinationLat == null || _destinationLon == null) return;

    // Check if we've moved enough to warrant an update
    if (_lastRouteUpdatePosition != null) {
      final distanceMoved = PlacesService.calculateDistance(
        _lastRouteUpdatePosition!.latitude,
        _lastRouteUpdatePosition!.longitude,
        currentPosition.latitude,
        currentPosition.longitude,
      );

      if (distanceMoved < _minDistanceForRouteUpdateMeters) {
        return; // Not moved enough
      }
    }

    _lastRouteUpdatePosition = currentPosition;

    // Check if we've reached the destination (within 20 meters)
    final distanceToDestination = PlacesService.calculateDistance(
      currentPosition.latitude,
      currentPosition.longitude,
      _destinationLat!,
      _destinationLon!,
    );

    if (distanceToDestination < 20.0) {
      // Reached destination!
      _clearRoute();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Destination reached!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final routePoints = _currentRoute!.points;

    // Find the closest point on the route to current position
    double minDistance = double.infinity;
    int closestPointIndex = 0;

    for (int i = 0; i < routePoints.length; i++) {
      final distance = PlacesService.calculateDistance(
        currentPosition.latitude,
        currentPosition.longitude,
        routePoints[i].latitude,
        routePoints[i].longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestPointIndex = i;
      }
    }

    // Check if user is off-route
    if (minDistance > _offRouteThresholdMeters) {
      print('User is off-route (${minDistance.toStringAsFixed(1)}m away). Recalculating...');

      // Recalculate route from current position to destination
      final newRoute = await DirectionsService.getRoute(
        originLat: currentPosition.latitude,
        originLng: currentPosition.longitude,
        destLat: _destinationLat!,
        destLng: _destinationLon!,
      );

      if (newRoute != null && mounted) {
        setState(() {
          _currentRouteInfo = newRoute;
          _currentRoute = Polyline(
            polylineId: PolylineId('route_${DateTime.now().millisecondsSinceEpoch}'),
            points: newRoute.polylinePoints,
            color: Colors.blue,
            width: kIsWeb ? 6 : 5,
            geodesic: !kIsWeb,
            visible: true,
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Route updated: ${newRoute.distance}, ETA: ${newRoute.duration}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // User is on route - trim the polyline to remove passed points
      if (closestPointIndex > 0) {
        final remainingPoints = routePoints.sublist(closestPointIndex);

        if (remainingPoints.length > 1 && mounted) {
          setState(() {
            _currentRoute = Polyline(
              polylineId: _currentRoute!.polylineId,
              points: remainingPoints,
              color: Colors.blue,
              width: kIsWeb ? 6 : 5,
              geodesic: !kIsWeb,
              visible: true,
            );
          });

          print('Trimmed ${closestPointIndex} passed waypoints. ${remainingPoints.length} points remaining.');
        }
      }
    }
  }

  /// Map Firestore docs -> FacilityPin list.
  List<FacilityPin> _pinsFromSnapshot(QuerySnapshot snap) {
    return snap.docs
        .map((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};

          // Fields
          final String name = (data['name'] ?? 'Unnamed').toString();
          final String category = (data['category'] ?? '').toString();

          // GeoPoint → doubles
          double lat = 0.0, lon = 0.0;
          final loc = data['location'];
          if (loc is GeoPoint) {
            lat = loc.latitude;
            lon = loc.longitude;
          }

          // Validate coordinates
          final valid = lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
          if (!valid) return null;

          // Pass extra fields for details sheet
          final meta = <String, dynamic>{
            'contactPerson': data['contactPerson'],
            'contactNumber': data['contactNumber'],
            'description': data['description'],
            'services': data['services'],
            'source': data['source'],
            'addedBy': data['addedBy'],
            'createdAt': data['createdAt'],
          };

          return FacilityPin(
            id: d.id,
            name: name,
            type: category, // <-- use category here
            lat: lat,
            lon: lon,
            meta: meta,
            source: 'manual',
          );
        })
        .whereType<FacilityPin>()
        .toList();
  }

  /// Map Firestore docs -> EmergencyAlert list.
  List<EmergencyAlert> _alertsFromSnapshot(QuerySnapshot snap) {
    return snap.docs
        .map((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};

          // GeoPoint → doubles
          double lat = 0.0, lon = 0.0;
          final loc = data['location'];
          if (loc is GeoPoint) {
            lat = loc.latitude;
            lon = loc.longitude;
          }

          // Validate coordinates
          final valid = lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
          if (!valid) return null;

          final services = (data['services'] as List?)
              ?.map((s) => s.toString())
              .toList() ?? [];

          final createdAtTimestamp = data['createdAt'] as Timestamp?;
          final createdAt = createdAtTimestamp?.toDate();

          return EmergencyAlert(
            id: d.id,
            userId: data['userId']?.toString() ?? '',
            userEmail: data['userEmail']?.toString() ?? 'Unknown',
            lon: lon,
            lat: lat,
            services: services,
            description: data['description']?.toString() ?? '',
            status: data['status']?.toString() ?? 'active',
            createdAt: createdAt,
          );
        })
        .whereType<EmergencyAlert>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final addLabel = _addMode ? "Tap on Map…" : "Add Facility";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Dispatcher Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),

      body: StreamBuilder<QuerySnapshot>(
        // Listen to facilities
        stream: FirebaseFirestore.instance.collection('facilities').snapshots(),
        builder: (context, facilitiesSnapshot) {
          final manualPins = (facilitiesSnapshot.hasData)
              ? _pinsFromSnapshot(facilitiesSnapshot.data!)
              : const <FacilityPin>[];

          // Merge manual and Google Places facilities
          final allPins = [...manualPins, ..._googlePlacesPins];

          // Nested StreamBuilder for emergency alerts
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('emergency_alerts')
                .where('status', isEqualTo: 'active')
                .snapshots(),
            builder: (context, alertsSnapshot) {
              final alerts = (alertsSnapshot.hasData)
                  ? _alertsFromSnapshot(alertsSnapshot.data!)
                  : const <EmergencyAlert>[];

              return MapView(
                controller: _mapController,
                enableTap: _addMode,
                onMapTap: _handleMapTap,
                facilities: allPins,
                onFacilityTap: _handleFacilityTap,
                emergencyAlerts: alerts,
                onEmergencyAlertTap: _handleEmergencyAlertTap,
                followUserLocation: false, // Dispatcher can freely pan the map
                routePolyline: _currentRoute,
              );
            },
          );
        },
      ),

      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Recenter button
          FloatingActionButton.small(
            heroTag: 'recenter',
            backgroundColor: Colors.blue,
            tooltip: 'Recenter on my location',
            onPressed: () {
              _mapController.recenterOnUserLocation();
            },
            child: const Icon(Icons.my_location, color: Colors.white),
          ),
          const SizedBox(height: 16),
          // Main Add Facility button
          FloatingActionButton.extended(
            heroTag: 'add_facility',
            backgroundColor: Colors.red,
            icon: Icon(_addMode ? Icons.touch_app : Icons.add_location_alt),
            label: Text(addLabel),
            onPressed: () {
              if (_addMode) {
                _mapController.clearTempPin();
                _disarmAddMode(showSnack: true);
              } else {
                _armAddMode();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _AddHereSheet extends StatelessWidget {
  final double lon;
  final double lat;
  final VoidCallback onAdd;
  final VoidCallback onCancel;

  const _AddHereSheet({
    required this.lon,
    required this.lat,
    required this.onAdd,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Add Facility Here?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text("Lat: ${lat.toStringAsFixed(6)}"),
            Text("Lon: ${lon.toStringAsFixed(6)}"),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAdd,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text("Add Facility"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyAlertSheet extends StatefulWidget {
  final EmergencyAlert alert;
  final Position? userLocation;
  final VoidCallback onNavigate;

  const _EmergencyAlertSheet({
    required this.alert,
    required this.userLocation,
    required this.onNavigate,
  });

  @override
  State<_EmergencyAlertSheet> createState() => _EmergencyAlertSheetState();
}

class _EmergencyAlertSheetState extends State<_EmergencyAlertSheet> {
  bool _resolving = false;
  bool _accepting = false;
  StreamSubscription<Position>? _locationUpdateSubscription;

  @override
  void dispose() {
    _locationUpdateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _acceptAlert() async {
    print('===== ACCEPTING ALERT =====');
    setState(() => _accepting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Not authenticated');
      }

      print('User: ${user.email} (${user.uid})');
      print('Alert ID: ${widget.alert.id}');

      // Update alert to mark as accepted
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .update({
        'acceptedBy': user.uid,
        'acceptedByEmail': user.email ?? 'Unknown',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      print('Alert marked as accepted in Firestore');

      // Start updating dispatcher location in real-time
      _startLocationUpdates();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alert accepted! Your location is being shared.'),
          backgroundColor: Colors.green,
        ),
      );

      // Auto-navigate to the alert
      widget.onNavigate();
    } catch (e) {
      print('Error accepting alert: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept alert: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _accepting = false);
      }
    }
  }

  Future<void> _startLocationUpdates() async {
    print('===== STARTING DISPATCHER LOCATION UPDATES =====');
    print('Alert ID: ${widget.alert.id}');

    try {
      // First, get current position to trigger permission request and get initial location
      print('Getting initial dispatcher location...');
      final currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      print('Initial dispatcher location: ${currentPosition.latitude}, ${currentPosition.longitude}');

      // Send initial location to Firestore
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .update({
        'dispatcherLocation': GeoPoint(currentPosition.latitude, currentPosition.longitude),
        'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
      });

      print('Initial dispatcher location sent to Firestore');

      // Then start streaming location updates
      _locationUpdateSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update every 5 meters
        ),
      ).listen((Position position) {
        print('Dispatcher location update: ${position.latitude}, ${position.longitude}');

        // Update dispatcher location in Firestore
        FirebaseFirestore.instance
            .collection('emergency_alerts')
            .doc(widget.alert.id)
            .update({
          'dispatcherLocation': GeoPoint(position.latitude, position.longitude),
          'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
        }).then((_) {
          print('Dispatcher location updated in Firestore successfully');
        }).catchError((error) {
          print('Error updating dispatcher location: $error');
        });
      }, onError: (error) {
        print('Error in location stream: $error');
      });
    } catch (e) {
      print('Error getting initial location: $e');
    }
  }

  Future<void> _resolveAlert() async {
    setState(() => _resolving = true);

    try {
      // Stop location updates
      _locationUpdateSubscription?.cancel();

      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .update({'status': 'resolved'});

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alert marked as resolved'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resolve alert: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _resolving = false);
      }
    }
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Unknown';
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .snapshots(),
      builder: (context, snapshot) {
        final alertData = snapshot.data?.data() as Map<String, dynamic>?;
        final isAccepted = alertData?['acceptedBy'] != null;
        final acceptedByEmail = alertData?['acceptedByEmail'] as String?;
        final currentUser = FirebaseAuth.instance.currentUser;
        final acceptedByMe = isAccepted && alertData?['acceptedBy'] == currentUser?.uid;

        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Accepted status banner
                  if (isAccepted)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: acceptedByMe ? Colors.blue.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: acceptedByMe ? Colors.blue : Colors.orange,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            acceptedByMe ? Icons.check_circle : Icons.info,
                            color: acceptedByMe ? Colors.blue : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              acceptedByMe
                                  ? 'You accepted this alert'
                                  : 'Accepted by $acceptedByEmail',
                              style: TextStyle(
                                color: acceptedByMe ? Colors.blue.shade900 : Colors.orange.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.emergency, color: Colors.red, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Emergency Alert',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatTimestamp(widget.alert.createdAt),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),

              // User info
              _InfoRow(
                icon: Icons.person,
                label: 'Reported by',
                value: widget.alert.userEmail,
              ),
              const SizedBox(height: 12),

              // Location
              _InfoRow(
                icon: Icons.location_on,
                label: 'Location',
                value: '${widget.alert.lat.toStringAsFixed(6)}, ${widget.alert.lon.toStringAsFixed(6)}',
              ),
              const SizedBox(height: 12),

              // Services needed
              const Row(
                children: [
                  Icon(Icons.local_hospital, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    'Services Needed',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.alert.services.map((service) {
                  return Chip(
                    label: Text(service),
                    backgroundColor: Colors.red.shade50,
                    labelStyle: const TextStyle(fontSize: 12),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Description
              const Row(
                children: [
                  Icon(Icons.description, size: 20, color: Colors.grey),
                  SizedBox(width: 8),
                  Text(
                    'Description',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.alert.description,
                  style: const TextStyle(fontSize: 14),
                ),
              ),

              const SizedBox(height: 24),

              // Navigate button
              if (widget.userLocation != null)
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onNavigate,
                        icon: const Icon(Icons.directions, color: Colors.white),
                        label: const Text(
                          'Navigate to Location',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),

                  // Action buttons
                  if (!isAccepted)
                    // Show Accept button if not accepted
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _accepting ? null : _acceptAlert,
                        icon: _accepting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle, color: Colors.white),
                        label: Text(
                          _accepting ? 'Accepting...' : 'Accept & Navigate',
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    )
                  else
                    // Show Close and Resolve buttons if accepted
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (acceptedByMe)
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _resolving ? null : _resolveAlert,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              child: _resolving
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Mark Resolved',
                                      style: TextStyle(color: Colors.white),
                                    ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FacilityDetailsSheet extends StatelessWidget {
  final FacilityPin facility;

  const _FacilityDetailsSheet({required this.facility});

  String _niceType(String t) {
    final s = t.trim();
    if (s.isEmpty) return 'Facility';
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final meta = facility.meta ?? const <String, dynamic>{};
    final isGooglePlace = facility.source == 'google_places';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "${_niceType(facility.type)} — ${facility.name}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isGooglePlace)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Google',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text("Lat: ${facility.lat.toStringAsFixed(6)}"),
              Text("Lon: ${facility.lon.toStringAsFixed(6)}"),
              const SizedBox(height: 8),

              // Google Places specific data
              if (isGooglePlace) ...[
                if (meta['address'] != null && meta['address'].toString().isNotEmpty)
                  Text("Address: ${meta['address']}"),
                if (meta['rating'] != null)
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text("${meta['rating']} / 5"),
                      if (meta['userRatingsTotal'] != null)
                        Text(" (${meta['userRatingsTotal']} reviews)"),
                    ],
                  ),
                if (meta['isOpenNow'] != null)
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: meta['isOpenNow'] ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        meta['isOpenNow'] ? 'Open now' : 'Closed',
                        style: TextStyle(
                          color: meta['isOpenNow'] ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
              ]
              // Manual facility specific data
              else ...[
                if (meta['contactPerson'] != null && meta['contactPerson'].toString().isNotEmpty)
                  Text("Contact: ${meta['contactPerson']}"),
                if (meta['contactNumber'] != null && meta['contactNumber'].toString().isNotEmpty)
                  Text("Phone: ${meta['contactNumber']}"),
                if (meta['description'] != null && meta['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text("Description: ${meta['description']}"),
                ],
                if (meta['services'] != null && meta['services'] is List && (meta['services'] as List).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text("Services: ${(meta['services'] as List).join(', ')}"),
                ],
              ],

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
