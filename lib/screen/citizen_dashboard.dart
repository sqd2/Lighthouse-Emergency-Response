import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/map_view.dart';
import '../widgets/sos_widgets.dart';
import '../widgets/facility_details_widget.dart';
import '../widgets/notification_permission_banner.dart';
import '../widgets/medical_info_banner.dart';
import '../models/facility_pin.dart';
import '../mixins/route_navigation_mixin.dart';
import '../mixins/location_tracking_mixin.dart';
import '../services/notification_service.dart';
import '../services/medical_info_service.dart';
import '../places_service.dart';
import '../directions_service.dart';
import 'login_screen.dart';
import 'edit_profile_screen.dart';

class CitizenDashboard extends StatefulWidget {
  const CitizenDashboard({super.key});

  @override
  State<CitizenDashboard> createState() => _CitizenDashboardState();
}

class _CitizenDashboardState extends State<CitizenDashboard>
    with RouteNavigationMixin, LocationTrackingMixin {
  // Dispatcher tracking
  Polyline? _dispatcherRoute;
  GeoPoint? _lastDispatcherLocation; // Track last known dispatcher location

  // Medical info tracking
  bool _hasMedicalInfo = false;
  bool _medicalInfoChecked = false;

  /// Calculate distance between two GeoPoints in meters
  String _calculateDistanceBetween(GeoPoint point1, GeoPoint point2) {
    final distance = Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(2)} km';
    }
  }

  @override
  void initState() {
    super.initState();
    initializeLocationTracking(
      onLocationUpdate: (position) {
        // Update route if we have an active route
        if (currentRoute != null &&
            destinationLat != null &&
            destinationLon != null) {
          updateRouteProgress(context, position);
        }
      },
    );
    _setUserRole();
    // Delay notification initialization to ensure Firebase is ready
    Future.delayed(const Duration(seconds: 2), () {
      _initializeNotifications();
    });
    // Check if user has medical info
    _checkMedicalInfo();
  }

  Future<void> _checkMedicalInfo() async {
    try {
      final hasMedicalInfo = await MedicalInfoService.hasMedicalInfo();
      if (mounted) {
        setState(() {
          _hasMedicalInfo = hasMedicalInfo;
          _medicalInfoChecked = true;
        });
      }
    } catch (e) {
      print('Error checking medical info: $e');
      if (mounted) {
        setState(() {
          _medicalInfoChecked = true;
        });
      }
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      await NotificationService.initialize();
    } catch (e) {
      print('Failed to initialize notifications in citizen dashboard: $e');
    }
  }

  Future<void> _setUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
      'role': 'citizen',
      'email': user.email,
    }, SetOptions(merge: true));
  }

  @override
  void dispose() {
    disposeLocationTracking();
    super.dispose();
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
      builder: (_) => FacilityDetailsSheet(
        facility: f,
        userLocation: userLocation,
        onNavigate: () => _navigateToFacility(f),
      ),
    );
  }

  Future<void> _navigateToFacility(FacilityPin facility) async {
    if (userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to get your location'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await navigateToLocation(
      context: context,
      userLocation: userLocation!,
      destLat: facility.lat,
      destLng: facility.lon,
      locationName: facility.name,
    );
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
            width: 6,
            geodesic: true,
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
      builder: (context) => SOSSheet(userLocation: userLocation),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Citizen Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EditProfileScreen(),
                ),
              );
            },
            tooltip: 'Edit Profile',
          ),
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
          final allPins = [...manualPins, ...googlePlacesPins];

          // Check for active SOS alerts by current user
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('emergency_alerts')
                .where('userId', isEqualTo: user?.uid ?? '')
                .where('status', isEqualTo: 'active')
                .snapshots(),
            builder: (context, alertSnapshot) {
              // Log every time StreamBuilder rebuilds
              if (alertSnapshot.hasData && alertSnapshot.data!.docs.isNotEmpty) {
                final alertDoc = alertSnapshot.data!.docs.first;
                final data = alertDoc.data() as Map<String, dynamic>;
                if (data['dispatcherLocation'] != null) {
                  final loc = data['dispatcherLocation'] as GeoPoint;
                  print('[STREAM UPDATE] Dispatcher location from Firestore: ${loc.latitude}, ${loc.longitude}');
                }
              }

              final hasActiveAlert =
                  alertSnapshot.hasData && alertSnapshot.data!.docs.isNotEmpty;
              final activeAlert = hasActiveAlert
                  ? alertSnapshot.data!.docs.first
                  : null;
              final alertData = activeAlert?.data() as Map<String, dynamic>?;

              // Extract dispatcher location for real-time tracking
              LatLng? dispatcherLocation;
              String? dispatcherName;

              // Update dispatcher location and route if accepted
              if (alertData != null &&
                  alertData['dispatcherLocation'] != null) {
                final dispatcherLoc =
                    alertData['dispatcherLocation'] as GeoPoint;
                final alertLoc = alertData['location'] as GeoPoint;

                // Set dispatcher location for MapView
                dispatcherLocation = LatLng(
                  dispatcherLoc.latitude,
                  dispatcherLoc.longitude,
                );
                dispatcherName = alertData['acceptedByEmail'] ?? 'Dispatcher';

                // Only calculate route when dispatcher location actually changes
                final locationChanged = _lastDispatcherLocation == null ||
                    _lastDispatcherLocation!.latitude != dispatcherLoc.latitude ||
                    _lastDispatcherLocation!.longitude != dispatcherLoc.longitude;

                if (locationChanged) {
                  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
                  print('🔄 DISPATCHER MOVED!');
                  print('   Previous: ${_lastDispatcherLocation?.latitude}, ${_lastDispatcherLocation?.longitude}');
                  print('   Current:  ${dispatcherLoc.latitude}, ${dispatcherLoc.longitude}');
                  print('   Distance: ${_lastDispatcherLocation != null ? _calculateDistanceBetween(_lastDispatcherLocation!, dispatcherLoc) : "N/A"}');
                  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
                  _lastDispatcherLocation = dispatcherLoc;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _updateDispatcherRoute(dispatcherLoc, alertLoc);
                  });
                }
              } else {
                if (alertData != null) {
                  print('Alert exists but no dispatcher location');
                  print('acceptedBy: ${alertData['acceptedBy']}');
                  print(
                    'dispatcherLocation: ${alertData['dispatcherLocation']}',
                  );
                }
                if (_dispatcherRoute != null || _lastDispatcherLocation != null) {
                  print('Clearing dispatcher route and location tracking');
                  _dispatcherRoute = null;
                  _lastDispatcherLocation = null;
                }
              }

              return Stack(
                children: [
                  MapView(
                    facilities: allPins,
                    onFacilityTap: _handleFacilityTap,
                    routePolyline: _dispatcherRoute ?? currentRoute,
                    dispatcherLocation: dispatcherLocation,
                    dispatcherName: dispatcherName,
                  ),

                  // Active SOS Alert Banner
                  if (hasActiveAlert)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: ActiveSOSBanner(
                        alertId: activeAlert!.id,
                        alertData: alertData ?? {},
                      ),
                    ),

                  // Notification Permission Banner (ALWAYS ON TOP)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: NotificationPermissionBanner(),
                  ),

                  // Medical Info Banner (below notification banner)
                  if (_medicalInfoChecked && !_hasMedicalInfo && !hasActiveAlert)
                    Positioned(
                      top: 60,
                      left: 0,
                      right: 0,
                      child: MedicalInfoBanner(
                        onComplete: () {
                          // Refresh medical info status when user completes the form
                          _checkMedicalInfo();
                        },
                        onDismiss: () {
                          // User dismissed the banner, mark as having medical info
                          // to prevent showing again this session
                          setState(() {
                            _hasMedicalInfo = true;
                          });
                        },
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
