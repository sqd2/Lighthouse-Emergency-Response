import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/map_view.dart';
import '../widgets/facility_details_widget.dart';
import '../widgets/emergency_alert_widget.dart';
import '../widgets/notification_permission_banner.dart';
import '../widgets/dispatcher_side_panel.dart';
import '../widgets/incoming_call_dialog.dart';
import '../widgets/facility_filter_widget.dart';
import '../models/facility_pin.dart';
import '../models/emergency_alert.dart';
import '../models/call.dart';
import '../mixins/route_navigation_mixin.dart';
import '../mixins/location_tracking_mixin.dart';
import '../services/notification_service.dart';
import '../services/alert_history_service.dart';
import 'add_facility_screen.dart';
import 'dispatcher_settings_screen.dart';

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

  // Debug mode: when true, shows pins, alerts, debug HUD, and logs
  bool _debugMode = false;

  // Controller to clear the temporary pin on Cancel/Add
  final _mapController = MapViewController();

  // Track accepted alert ID for location sharing
  String? _activeAlertId;
  StreamSubscription<Position>? _alertLocationStream;
  Position? _lastSharedPosition; // Track last position to implement manual distance filter

  // Call listener
  StreamSubscription<QuerySnapshot>? _callListener;

  // Tab navigation (no PageView - full screen tabs)
  int _currentPageIndex = 1; // Start on Map tab

  // Facility filtering
  bool _showFacilityFilter = false;
  List<FacilityPin> _filteredFacilities = [];

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

        // Update dispatcher's last known location in Firestore if active
        _updateLastKnownLocation(position);
      },
    );
    _loadActiveStatus();
    // Delay notification initialization to ensure Firebase is ready
    Future.delayed(const Duration(seconds: 2), () {
      _initializeNotifications();
    });
    _setupCallListener();
  }

  /// Update dispatcher's last known location in Firestore (only if active)
  Future<void> _updateLastKnownLocation(Position position) async {
    if (!_isActive) return; // Only update when active

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'lastKnownLocation': GeoPoint(position.latitude, position.longitude),
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating last known location: $e');
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      await NotificationService.initialize();
    } catch (e) {
      print('Failed to initialize notifications in dispatcher dashboard: $e');
    }
  }

  /// Set up listener for incoming calls
  void _setupCallListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Use collectionGroup to listen to all calls across all alerts
    _callListener = FirebaseFirestore.instance
        .collectionGroup('calls')
        .where('receiverId', isEqualTo: user.uid)
        .where('status', isEqualTo: Call.STATUS_RINGING)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final call = Call.fromFirestore(change.doc);

          // Extract alertId from the document path
          // Path format: emergency_alerts/{alertId}/calls/{callId}
          final pathSegments = change.doc.reference.path.split('/');
          if (pathSegments.length >= 2) {
            final alertId = pathSegments[pathSegments.length - 3];

            // Show incoming call dialog
            if (mounted) {
              showIncomingCallDialog(context, alertId, call);
            }
          }
        }
      }
    });
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
        _debugMode = doc.data()?['debugMode'] ?? false;
      });
    }
  }

  Future<void> _toggleActiveStatus(bool newStatus) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Prepare data to update
      final updateData = {
        'isActive': newStatus,
        'role': 'dispatcher',
        'email': user.email,
      };

      // If going active, set initial location
      if (newStatus && userLocation != null) {
        updateData['lastKnownLocation'] = GeoPoint(
          userLocation!.latitude,
          userLocation!.longitude,
        );
        updateData['lastLocationUpdate'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _isActive = newStatus;
        });

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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleDebugMode(bool newStatus) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'debugMode': newStatus}, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _debugMode = newStatus;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus
                  ? 'Debug mode enabled - showing all debug info'
                  : 'Debug mode disabled - hiding debug info',
            ),
            backgroundColor: newStatus ? Colors.orange : Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update debug mode: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    disposeLocationTracking();
    _alertLocationStream?.cancel();
    _callListener?.cancel();
    super.dispose();
  }

  void _onBottomNavTap(int index) {
    setState(() {
      _currentPageIndex = index;
    });
  }

  /// Start sharing dispatcher location for an accepted alert
  Future<void> startSharingLocationForAlert(String alertId) async {
    print('[DASHBOARD] Starting location sharing');
    print('  Alert ID: $alertId');

    // Cancel any existing stream
    _alertLocationStream?.cancel();
    _activeAlertId = alertId;

    try {
      //Get initial position
      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      print('[LOCATION] Initial position: ${initialPosition.latitude}, ${initialPosition.longitude}');

      // Write to Firestore
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alertId)
          .update({
        'dispatcherLocation': GeoPoint(initialPosition.latitude, initialPosition.longitude),
        'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
      });

      print('[LOCATION] Initial location written');
      _lastSharedPosition = initialPosition;

      // Start stream (web doesn't honor distanceFilter, so we manually check)
      _alertLocationStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen((position) async {
        if (_activeAlertId != alertId) return;

        // MANUAL DISTANCE FILTER - web platform doesn't honor distanceFilter
        if (_lastSharedPosition != null) {
          final distanceMoved = Geolocator.distanceBetween(
            _lastSharedPosition!.latitude,
            _lastSharedPosition!.longitude,
            position.latitude,
            position.longitude,
          );

          if (distanceMoved < 5.0) {
            // Skip update - haven't moved enough
            return;
          }
        }

        print('[UPDATE] Position: ${position.latitude}, ${position.longitude}');
        _lastSharedPosition = position;

        try {
          // Fetch alert to check for geofence arrival
          final alertDoc = await FirebaseFirestore.instance
              .collection('emergency_alerts')
              .doc(alertId)
              .get();

          if (!alertDoc.exists) {
            print('[WARN] Alert document no longer exists');
            return;
          }

          final alertData = alertDoc.data();
          final status = alertData?['status'] as String?;
          final location = alertData?['location'] as GeoPoint?;

          print('[DEBUG] Alert status: $status, Location exists: ${location != null}');

          // Update dispatcher location
          await FirebaseFirestore.instance
              .collection('emergency_alerts')
              .doc(alertId)
              .update({
            'dispatcherLocation': GeoPoint(position.latitude, position.longitude),
            'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
          });

          print('[LOCATION] Written to Firestore');

          // Automatic geofence arrival detection (50 meters)
          if (status == EmergencyAlert.STATUS_ACTIVE && location != null) {
            final distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              location.latitude,
              location.longitude,
            );

            print('[GEOFENCE] Distance to alert: ${distance.toStringAsFixed(1)}m (status: $status)');

            if (distance <= 50) {
              print('[AUTO-ARRIVAL] Within 50m geofence, marking as arrived...');
              await FirebaseFirestore.instance
                  .collection('emergency_alerts')
                  .doc(alertId)
                  .update({
                'status': EmergencyAlert.STATUS_ARRIVED,
                'arrivedAt': FieldValue.serverTimestamp(),
              });
              print('[AUTO-ARRIVAL] Successfully marked as arrived');
            }
          } else {
            if (status != EmergencyAlert.STATUS_ACTIVE) {
              print('[SKIP GEOFENCE] Status is not active: $status');
            }
            if (location == null) {
              print('[SKIP GEOFENCE] Alert location is null');
            }
          }
        } catch (e) {
          print('[ERROR] Location update failed: $e');
        }
      });

      print('[STREAM] Location stream started');
    } catch (e) {
      print('[ERROR] Failed to start location sharing: $e');
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
        onAccepted: (alertId) => startSharingLocationForAlert(alertId),
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
    return Scaffold(
      appBar: _currentPageIndex != 0 ? AppBar(
        title: Text(_getPageTitle()),
      ) : null,
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
                .where('status', whereIn: [
                  EmergencyAlert.STATUS_PENDING,
                  EmergencyAlert.STATUS_ACTIVE,
                  EmergencyAlert.STATUS_ARRIVED,
                ])
                .snapshots(),
            builder: (context, alertsSnapshot) {
              final alerts = (alertsSnapshot.hasData)
                  ? _alertsFromSnapshot(alertsSnapshot.data!)
                  : const <EmergencyAlert>[];

              // Full-screen tab navigation (no PageView, no gesture conflicts)
              return IndexedStack(
                index: _currentPageIndex,
                children: [
                  // Tab 0: Dashboard
                  _buildDashboardPage(),

                  // Tab 1: Map (Full Screen)
                  _buildMapPage(allPins, alerts),

                  // Tab 2: Settings
                  _buildSettingsPage(),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentPageIndex,
        onTap: _onBottomNavTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  String _getPageTitle() {
    switch (_currentPageIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Map';
      case 2:
        return 'Settings';
      default:
        return 'Dispatcher';
    }
  }

  Widget _buildDashboardPage() {
    return DispatcherSidePanel(
      userLocation: userLocation,
      onNavigateToAlert: _navigateToAlert,
      onAcceptAlert: startSharingLocationForAlert,
    );
  }

  Widget _buildMapPage(List<FacilityPin> allPins, List<EmergencyAlert> alerts) {
    // Use filtered facilities if filter is active, otherwise show all
    final displayFacilities = _filteredFacilities.isEmpty ? allPins : _filteredFacilities;

    return Stack(
      children: [
        MapView(
          controller: _mapController,
          enableTap: _addMode,
          onMapTap: _handleMapTap,
          facilities: displayFacilities,
          onFacilityTap: _handleFacilityTap,
          emergencyAlerts: alerts,
          onEmergencyAlertTap: _handleEmergencyAlertTap,
          followUserLocation: false,
          routePolyline: currentRoute,
          debugMode: _debugMode,
        ),

        // Notification Permission Banner
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: NotificationPermissionBanner(),
        ),

        // Fixed Corner Buttons (Google Maps style) - Bottom Left
        // Add Facility Button
        Positioned(
          left: 16,
          bottom: 96,
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: FloatingActionButton(
              heroTag: 'add_facility',
              onPressed: () {
                if (_addMode) {
                  _mapController.clearTempPin();
                  _disarmAddMode(showSnack: true);
                } else {
                  _armAddMode();
                }
              },
              backgroundColor: _addMode ? Colors.orange : Colors.red,
              child: Icon(_addMode ? Icons.close : Icons.add_location_alt),
            ),
          ),
        ),

        // Recenter Button
        Positioned(
          left: 16,
          bottom: 24,
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: FloatingActionButton(
              heroTag: 'recenter',
              onPressed: () {
                _mapController.recenterOnUserLocation();
              },
              backgroundColor: Colors.blue,
              child: const Icon(Icons.my_location),
            ),
          ),
        ),

        // Filter Button - Top Right
        Positioned(
          right: 16,
          top: 80,
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: FloatingActionButton(
              heroTag: 'filter',
              onPressed: () {
                setState(() {
                  _showFacilityFilter = !_showFacilityFilter;
                  // Reset filter when closing
                  if (!_showFacilityFilter) {
                    _filteredFacilities = [];
                  }
                });
              },
              backgroundColor: _showFacilityFilter ? Colors.green : Colors.white,
              child: Icon(
                Icons.filter_list,
                color: _showFacilityFilter ? Colors.white : Colors.grey[700],
              ),
            ),
          ),
        ),

        // Filter Widget Overlay
        if (_showFacilityFilter)
          Positioned(
            top: 140,
            right: 16,
            left: 16,
            child: FacilityFilterWidget(
              allFacilities: allPins,
              onFilteredFacilities: (filtered) {
                setState(() {
                  _filteredFacilities = filtered;
                });
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    return DispatcherSettingsScreen(
      isActive: _isActive,
      debugMode: _debugMode,
      onActiveToggle: _toggleActiveStatus,
      onDebugModeToggle: _toggleDebugMode,
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
