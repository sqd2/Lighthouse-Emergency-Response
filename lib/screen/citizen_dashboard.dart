import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/map_view.dart';
import '../widgets/sos_widgets.dart';
import '../widgets/facility_details_widget.dart';
import '../models/facility_pin.dart';
import '../mixins/route_navigation_mixin.dart';
import '../mixins/location_tracking_mixin.dart';
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
  FacilityPin? _dispatcherMarker;

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
                    routePolyline: _dispatcherRoute ?? currentRoute,
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
