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
import 'package:ligthouse/screen/login_screen.dart';

class CitizenDashboard extends StatefulWidget {
  const CitizenDashboard({super.key});

  @override
  State<CitizenDashboard> createState() => _CitizenDashboardState();
}

class _CitizenDashboardState extends State<CitizenDashboard> {
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

  // Dispatcher tracking
  Polyline? _dispatcherRoute;
  FacilityPin? _dispatcherMarker;

  // Search radius in meters (5km)
  static const int _searchRadiusMeters = 5000;

  // Route tracking thresholds
  static const double _offRouteThresholdMeters =
      50.0; // How far off route before recalculating
  static const double _minDistanceForRouteUpdateMeters =
      20.0; // Min distance moved before checking route

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
    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter:
                10, // Update every 10 meters for better route tracking
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
            if (_currentRoute != null &&
                _destinationLat != null &&
                _destinationLon != null) {
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
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Logout failed: $e")));
    }
  }

  void _handleFacilityTap(FacilityPin f) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _FacilityDetailsSheet(
        facility: f,
        userLocation: _userLocation,
        onNavigate: () => _navigateToFacility(f),
      ),
    );
  }

  Future<void> _navigateToFacility(FacilityPin facility) async {
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
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
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
    print('Destination: ${facility.lat}, ${facility.lon}');

    final route = await DirectionsService.getRoute(
      originLat: _userLocation!.latitude,
      originLng: _userLocation!.longitude,
      destLat: facility.lat,
      destLng: facility.lon,
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
      print(
        'WARNING: Only ${route.polylinePoints.length} points - this will be a straight line!',
      );
    }

    // Show first, middle, and last points
    print(
      'First point: ${route.polylinePoints.first.latitude}, ${route.polylinePoints.first.longitude}',
    );
    if (route.polylinePoints.length > 2) {
      final midIndex = route.polylinePoints.length ~/ 2;
      print(
        'Middle point: ${route.polylinePoints[midIndex].latitude}, ${route.polylinePoints[midIndex].longitude}',
      );
    }
    print(
      'Last point: ${route.polylinePoints.last.latitude}, ${route.polylinePoints.last.longitude}',
    );

    // Validate all coordinates are reasonable
    for (int i = 0; i < route.polylinePoints.length; i++) {
      final point = route.polylinePoints[i];
      if (point.latitude < -90 ||
          point.latitude > 90 ||
          point.longitude < -180 ||
          point.longitude > 180) {
        print(
          'ERROR: Invalid coordinate at index $i: ${point.latitude}, ${point.longitude}',
        );
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
    print(
      'Creating polyline with unique ID: route_${DateTime.now().millisecondsSinceEpoch}',
    );

    setState(() {
      _currentRouteInfo = route;
      _destinationLat = facility.lat;
      _destinationLon = facility.lon;
      _lastRouteUpdatePosition = _userLocation;
      // Use unique polylineId to force re-render
      // Note: geodesic doesn't work well on web, but the detailed polyline points should be sufficient
      _currentRoute = Polyline(
        polylineId: PolylineId(
          'route_${DateTime.now().millisecondsSinceEpoch}',
        ),
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
        content: Text(
          'Route: ${route.distance} (${route.polylinePoints.length} points), ETA: ${route.duration}',
        ),
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
      print(
        'User is off-route (${minDistance.toStringAsFixed(1)}m away). Recalculating...',
      );

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
            polylineId: PolylineId(
              'route_${DateTime.now().millisecondsSinceEpoch}',
            ),
            points: newRoute.polylinePoints,
            color: Colors.blue,
            width: kIsWeb ? 6 : 5,
            geodesic: !kIsWeb,
            visible: true,
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Route updated: ${newRoute.distance}, ETA: ${newRoute.duration}',
            ),
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

          print(
            'Trimmed ${closestPointIndex} passed waypoints. ${remainingPoints.length} points remaining.',
          );
        }
      }
    }
  }

  /// Map Firestore docs -> FacilityPin list (for manual facilities).
  List<FacilityPin> _pinsFromSnapshot(QuerySnapshot snap) {
    return snap.docs
        .map((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};

          final String name = (data['name'] ?? 'Unnamed').toString();
          final String category = (data['category'] ?? '').toString();

          double lat = 0.0, lon = 0.0;
          final loc = data['location'];
          if (loc is GeoPoint) {
            lat = loc.latitude;
            lon = loc.longitude;
          }

          final valid = lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
          if (!valid) return null;

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
            type: category,
            lat: lat,
            lon: lon,
            meta: meta,
            source: 'manual',
          );
        })
        .whereType<FacilityPin>()
        .toList();
  }

  Future<void> _updateDispatcherRoute(
    GeoPoint dispatcherLoc,
    GeoPoint alertLoc,
  ) async {
    print('===== CALCULATING DISPATCHER ROUTE =====');
    print(
      'Dispatcher location: ${dispatcherLoc.latitude}, ${dispatcherLoc.longitude}',
    );
    print('Alert location: ${alertLoc.latitude}, ${alertLoc.longitude}');

    try {
      final route = await DirectionsService.getRoute(
        originLat: dispatcherLoc.latitude,
        originLng: dispatcherLoc.longitude,
        destLat: alertLoc.latitude,
        destLng: alertLoc.longitude,
      );

      if (route != null && mounted) {
        print(
          'Dispatcher route calculated: ${route.polylinePoints.length} points',
        );
        print('Route distance: ${route.distance}, duration: ${route.duration}');

        setState(() {
          _dispatcherRoute = Polyline(
            polylineId: PolylineId(
              'dispatcher_route_${DateTime.now().millisecondsSinceEpoch}',
            ),
            points: route.polylinePoints,
            color: Colors.green,
            width: kIsWeb ? 6 : 5,
            geodesic: !kIsWeb,
            visible: true,
          );
        });

        print('Dispatcher route polyline created and set in state');
      } else {
        print('Route calculation returned null');
      }
    } catch (e) {
      print('Error calculating dispatcher route: $e');
    }
  }

  void _showSOSDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SOSSheet(userLocation: _userLocation),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Citizen Dashboard -vnov'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('facilities').snapshots(),
        builder: (context, facilitiesSnapshot) {
          final manualPins = (facilitiesSnapshot.hasData)
              ? _pinsFromSnapshot(facilitiesSnapshot.data!)
              : const <FacilityPin>[];

          // Merge manual and Google Places facilities
          final allPins = [...manualPins, ..._googlePlacesPins];

          // Check for active SOS alerts by current user
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('emergency_alerts')
                .where('userId', isEqualTo: user?.uid ?? '')
                .where('status', isEqualTo: 'active')
                .snapshots(),
            builder: (context, alertSnapshot) {
              final hasActiveAlert =
                  alertSnapshot.hasData && alertSnapshot.data!.docs.isNotEmpty;
              final activeAlert = hasActiveAlert
                  ? alertSnapshot.data!.docs.first
                  : null;
              final alertData = activeAlert?.data() as Map<String, dynamic>?;

              // Update dispatcher location and route if accepted
              if (alertData != null &&
                  alertData['dispatcherLocation'] != null) {
                print('===== DISPATCHER TRACKING ACTIVE =====');
                print('Alert data has dispatcher location');

                final dispatcherLoc =
                    alertData['dispatcherLocation'] as GeoPoint;
                final alertLoc = alertData['location'] as GeoPoint;

                print(
                  'Dispatcher at: ${dispatcherLoc.latitude}, ${dispatcherLoc.longitude}',
                );
                print(
                  'Citizen at: ${alertLoc.latitude}, ${alertLoc.longitude}',
                );

                // Create dispatcher marker
                final newDispatcherMarker = FacilityPin(
                  id: 'dispatcher_${activeAlert!.id}',
                  name:
                      'Dispatcher (${alertData['acceptedByEmail'] ?? "Unknown"})',
                  type: 'dispatcher',
                  lat: dispatcherLoc.latitude,
                  lon: dispatcherLoc.longitude,
                );

                // Only update if location changed
                if (_dispatcherMarker == null ||
                    _dispatcherMarker!.lat != newDispatcherMarker.lat ||
                    _dispatcherMarker!.lon != newDispatcherMarker.lon) {
                  print(
                    'Dispatcher location changed, creating marker and route',
                  );
                  _dispatcherMarker = newDispatcherMarker;
                  // Calculate route asynchronously
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _updateDispatcherRoute(dispatcherLoc, alertLoc);
                  });
                } else {
                  print('Dispatcher location unchanged');
                }
              } else {
                if (alertData != null) {
                  print('Alert exists but no dispatcher location');
                  print('acceptedBy: ${alertData['acceptedBy']}');
                  print(
                    'dispatcherLocation: ${alertData['dispatcherLocation']}',
                  );
                }
                if (_dispatcherMarker != null || _dispatcherRoute != null) {
                  print('Clearing dispatcher marker and route');
                  _dispatcherMarker = null;
                  _dispatcherRoute = null;
                }
              }

              // Merge facilities with dispatcher marker
              final facilitiesWithDispatcher = _dispatcherMarker != null
                  ? [...allPins, _dispatcherMarker!]
                  : allPins;

              return Stack(
                children: [
                  MapView(
                    facilities: facilitiesWithDispatcher,
                    onFacilityTap: _handleFacilityTap,
                    routePolyline: _dispatcherRoute ?? _currentRoute,
                  ),

                  // Active SOS Alert Banner
                  if (hasActiveAlert)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: _ActiveSOSBanner(
                        alertId: activeAlert!.id,
                        alertData: alertData ?? {},
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showSOSDialog,
        backgroundColor: Colors.red,
        child: const Icon(Icons.sos, size: 32, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _SOSSheet extends StatefulWidget {
  final Position? userLocation;

  const _SOSSheet({required this.userLocation});

  @override
  State<_SOSSheet> createState() => _SOSSheetState();
}

class _SOSSheetState extends State<_SOSSheet> {
  final _descriptionController = TextEditingController();
  final _selectedServices = <String>{};
  bool _submitting = false;

  final _emergencyServices = [
    'Hospital',
    'Police Station',
    'Fire Station',
    'Ambulance',
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitSOS() async {
    // Validate
    if (_selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one emergency service'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe the emergency'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (widget.userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to get your location. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Create emergency alert in Firestore
      await FirebaseFirestore.instance.collection('emergency_alerts').add({
        'userId': user.uid,
        'userEmail': user.email ?? 'Unknown',
        'location': GeoPoint(
          widget.userLocation!.latitude,
          widget.userLocation!.longitude,
        ),
        'services': _selectedServices.toList(),
        'description': _descriptionController.text.trim(),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS alert sent! Help is on the way.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send SOS: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.sos, color: Colors.red, size: 28),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Emergency SOS',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Services selection
                  const Text(
                    'Select Emergency Services *',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Service chips
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _emergencyServices.map((service) {
                              final isSelected = _selectedServices.contains(
                                service,
                              );
                              return FilterChip(
                                label: Text(service),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedServices.add(service);
                                    } else {
                                      _selectedServices.remove(service);
                                    }
                                  });
                                },
                                selectedColor: Colors.red.shade100,
                                checkmarkColor: Colors.red,
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 24),

                          // Description
                          const Text(
                            'Describe the Emergency *',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: _descriptionController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText:
                                  'e.g., Car accident, medical emergency, fire...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Submit button
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _submitSOS,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Send SOS Alert',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _FacilityDetailsSheet extends StatelessWidget {
  final FacilityPin facility;
  final Position? userLocation;
  final VoidCallback onNavigate;

  const _FacilityDetailsSheet({
    required this.facility,
    required this.userLocation,
    required this.onNavigate,
  });

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
                if (meta['address'] != null &&
                    meta['address'].toString().isNotEmpty)
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
                if (meta['contactPerson'] != null &&
                    meta['contactPerson'].toString().isNotEmpty)
                  Text("Contact: ${meta['contactPerson']}"),
                if (meta['contactNumber'] != null &&
                    meta['contactNumber'].toString().isNotEmpty)
                  Text("Phone: ${meta['contactNumber']}"),
                if (meta['description'] != null &&
                    meta['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text("Description: ${meta['description']}"),
                ],
                if (meta['services'] != null &&
                    meta['services'] is List &&
                    (meta['services'] as List).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text("Services: ${(meta['services'] as List).join(', ')}"),
                ],
              ],

              const SizedBox(height: 16),

              // Navigate button
              if (userLocation != null)
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onNavigate,
                        icon: const Icon(Icons.directions, color: Colors.white),
                        label: const Text(
                          'Navigate to Facility',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),

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

class _ActiveSOSBanner extends StatefulWidget {
  final String alertId;
  final Map<String, dynamic> alertData;

  const _ActiveSOSBanner({required this.alertId, required this.alertData});

  @override
  State<_ActiveSOSBanner> createState() => _ActiveSOSBannerState();
}

class _ActiveSOSBannerState extends State<_ActiveSOSBanner> {
  bool _cancelling = false;

  Future<void> _cancelAlert() async {
    setState(() => _cancelling = true);

    try {
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alertId)
          .update({'status': 'cancelled'});

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS alert cancelled'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel alert: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cancelling = false);
      }
    }
  }

  void _showUpdateDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UpdateSOSSheet(
        alertId: widget.alertId,
        currentData: widget.alertData,
      ),
    );
  }

  void _showDetailsDialog() {
    final services =
        (widget.alertData['services'] as List?)
            ?.map((s) => s.toString())
            .toList() ??
        [];
    final description = widget.alertData['description']?.toString() ?? '';
    final createdAt = (widget.alertData['createdAt'] as Timestamp?)?.toDate();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sos, color: Colors.red),
            SizedBox(width: 8),
            Text('Active SOS Alert'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (createdAt != null)
              Text(
                'Sent ${_formatTimestamp(createdAt)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            const SizedBox(height: 16),
            const Text(
              'Services Requested:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: services.map((service) {
                return Chip(
                  label: Text(service),
                  backgroundColor: Colors.red.shade50,
                  labelStyle: const TextStyle(fontSize: 12),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Description:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(description),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final isAccepted = widget.alertData['acceptedBy'] != null;
    final acceptedByEmail = widget.alertData['acceptedByEmail'] as String?;
    final dispatcherLocation =
        widget.alertData['dispatcherLocation'] as GeoPoint?;
    final alertLocation = widget.alertData['location'] as GeoPoint?;

    // Calculate distance if dispatcher location is available
    String? distance;
    if (dispatcherLocation != null && alertLocation != null) {
      final distanceMeters = PlacesService.calculateDistance(
        dispatcherLocation.latitude,
        dispatcherLocation.longitude,
        alertLocation.latitude,
        alertLocation.longitude,
      );
      if (distanceMeters < 1000) {
        distance = '${distanceMeters.round()}m away';
      } else {
        distance = '${(distanceMeters / 1000).toStringAsFixed(1)}km away';
      }
    }

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: isAccepted ? Colors.green.shade50 : Colors.red.shade50,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isAccepted ? Colors.green : Colors.red,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isAccepted ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isAccepted ? Icons.check_circle : Icons.emergency,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAccepted ? 'Dispatcher En Route' : 'Active SOS Alert',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isAccepted
                              ? Colors.green.shade700
                              : Colors.red,
                        ),
                      ),
                      Text(
                        isAccepted
                            ? acceptedByEmail ?? 'Unknown dispatcher'
                            : 'Help is on the way',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                      if (isAccepted && distance != null)
                        Text(
                          distance,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.info_outline,
                    color: isAccepted ? Colors.green : Colors.red,
                  ),
                  onPressed: _showDetailsDialog,
                  tooltip: 'View details',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showUpdateDialog,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Update'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _cancelling ? null : _cancelAlert,
                    icon: _cancelling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.close, size: 16),
                    label: const Text('Cancel SOS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
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

class _UpdateSOSSheet extends StatefulWidget {
  final String alertId;
  final Map<String, dynamic> currentData;

  const _UpdateSOSSheet({required this.alertId, required this.currentData});

  @override
  State<_UpdateSOSSheet> createState() => _UpdateSOSSheetState();
}

class _UpdateSOSSheetState extends State<_UpdateSOSSheet> {
  late TextEditingController _descriptionController;
  late Set<String> _selectedServices;
  bool _updating = false;

  final _emergencyServices = [
    'Hospital',
    'Police Station',
    'Fire Station',
    'Ambulance',
  ];

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.currentData['description']?.toString() ?? '',
    );
    _selectedServices = Set<String>.from(
      (widget.currentData['services'] as List?)?.map((s) => s.toString()) ?? [],
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _updateAlert() async {
    // Validate
    if (_selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one emergency service'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe the emergency'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _updating = true);

    try {
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alertId)
          .update({
            'services': _selectedServices.toList(),
            'description': _descriptionController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS alert updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update alert: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.orange,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Update SOS Alert',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Services selection
                          const Text(
                            'Select Emergency Services *',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),

                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _emergencyServices.map((service) {
                              final isSelected = _selectedServices.contains(
                                service,
                              );
                              return FilterChip(
                                label: Text(service),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedServices.add(service);
                                    } else {
                                      _selectedServices.remove(service);
                                    }
                                  });
                                },
                                selectedColor: Colors.orange.shade100,
                                checkmarkColor: Colors.orange,
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 24),

                          // Description
                          const Text(
                            'Describe the Emergency *',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: _descriptionController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText:
                                  'e.g., Car accident, medical emergency, fire...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Update button
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _updating ? null : _updateAlert,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _updating
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Update SOS Alert',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
