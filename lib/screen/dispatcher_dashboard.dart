import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/map_view.dart';
import '../widgets/facility_details_widget.dart';
import '../widgets/emergency_alert_widget.dart';
import '../models/facility_pin.dart';
import '../models/emergency_alert.dart';
import '../mixins/route_navigation_mixin.dart';
import '../mixins/location_tracking_mixin.dart';
import '../services/notification_service.dart';
import 'add_facility_screen.dart';
import 'edit_profile_screen.dart';

class DispatcherDashboard extends StatefulWidget {
  const DispatcherDashboard({super.key});

  @override
  State<DispatcherDashboard> createState() => _DispatcherDashboardState();
}

class _DispatcherDashboardState extends State<DispatcherDashboard>
    with RouteNavigationMixin, LocationTrackingMixin {
  double? _pendingLon;
  double? _pendingLat;

  // Add Mode toggle: when true, MapView captures the next tap for temp pin
  bool _addMode = false;

  // Active status: when true, dispatcher receives SOS notifications
  bool _isActive = false;

  // Controller to clear the temporary pin on Cancel/Add
  final _mapController = MapViewController();

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
    _initializeNotifications();
    _loadActiveStatus();
  }

  Future<void> _initializeNotifications() async {
    await NotificationService.initialize();
  }

  Future<void> _loadActiveStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (doc.exists && mounted) {
      setState(() {
        _isActive = doc.data()?['isActive'] ?? false;
      });
    }
  }

  Future<void> _toggleActiveStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final newStatus = !_isActive;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
      'isActive': newStatus,
      'role': 'dispatcher',
      'email': user.email,
    }, SetOptions(merge: true));

    setState(() {
      _isActive = newStatus;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus
                ? 'You are now ACTIVE - will receive SOS notifications'
                : 'You are now INACTIVE - will not receive SOS notifications',
          ),
          backgroundColor: newStatus ? Colors.green : Colors.grey,
        ),
      );
    }
  }

  @override
  void dispose() {
    disposeLocationTracking();
    super.dispose();
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
      builder: (_) => FacilityDetailsSheet(facility: f),
    );
  }

  void _handleEmergencyAlertTap(EmergencyAlert alert) {
    showModalBottomSheet(
      context: context,
      builder: (_) => EmergencyAlertSheet(
        alert: alert,
        userLocation: userLocation,
        onNavigate: () => _navigateToAlert(alert),
      ),
    );
  }

  Future<void> _navigateToAlert(EmergencyAlert alert) async {
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
      destLat: alert.lat,
      destLng: alert.lon,
      locationName: 'Emergency Alert',
    );
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
        // Listen to facilities
        stream: FirebaseFirestore.instance.collection('facilities').snapshots(),
        builder: (context, facilitiesSnapshot) {
          final manualPins = (facilitiesSnapshot.hasData)
              ? _pinsFromSnapshot(facilitiesSnapshot.data!)
              : const <FacilityPin>[];

          // Merge manual and Google Places facilities
          final allPins = [...manualPins, ...googlePlacesPins];

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
                routePolyline: currentRoute,
              );
            },
          );
        },
      ),

      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Active/Inactive toggle
          FloatingActionButton.extended(
            heroTag: 'active_status',
            backgroundColor: _isActive ? Colors.green : Colors.grey,
            icon: Icon(
              _isActive ? Icons.notifications_active : Icons.notifications_off,
              color: Colors.white,
            ),
            label: Text(
              _isActive ? 'Active' : 'Inactive',
              style: const TextStyle(color: Colors.white),
            ),
            onPressed: _toggleActiveStatus,
          ),
          const SizedBox(height: 16),
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
