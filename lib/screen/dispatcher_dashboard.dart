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
import '../widgets/eta_display.dart';
import '../models/facility_pin.dart';
import '../models/emergency_alert.dart';
import '../models/call.dart';
import '../mixins/route_navigation_mixin.dart';
import '../mixins/location_tracking_mixin.dart';
import '../services/notification_service.dart';
import '../services/alert_history_service.dart';
import 'add_facility_screen.dart';
import 'dispatcher_settings_screen.dart';
import 'analytics_dashboard.dart';

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
  Position?
  _lastSharedPosition; // Track last position to implement manual distance filter
  GeoPoint?
  _alertDestination; // Cache alert location to avoid repeated Firestore reads

  // Call listener
  StreamSubscription<QuerySnapshot>? _callListener;

  // Tab navigation (no PageView - full screen tabs)
  int _currentPageIndex = 1; // Start on Map tab

  // Facility filtering state
  Set<String> _selectedFacilityTypes = {
    'hospital',
    'clinic',
    'police station',
    'fire station',
    'shelter',
  };
  bool _showAllFacilities = true;
  String? _highlightedFacilityId;
  String _facilitySearchQuery = '';
  List<FacilityPin> _currentFacilities = []; // Store for filter dialog

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
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {
          'lastKnownLocation': GeoPoint(position.latitude, position.longitude),
          'lastLocationUpdate': FieldValue.serverTimestamp(),
        },
      );
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
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'debugMode': newStatus,
      }, SetOptions(merge: true));

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
    _alertDestination = null; // Clear cached destination
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      print('[OK] Starting location sharing for alert...');

      // Fetch alert location ONCE and cache it (cost optimization)
      final alertDoc = await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alertId)
          .get();

      if (!alertDoc.exists) {
        throw Exception('Alert not found');
      }

      final alertData = alertDoc.data();
      _alertDestination = alertData?['location'] as GeoPoint?;

      if (_alertDestination == null) {
        throw Exception('Alert has no location');
      }

      print(
        '[CACHE] Alert destination cached: ${_alertDestination!.latitude}, ${_alertDestination!.longitude}',
      );

      //Get initial position with error handling
      Position? initialPosition;
      try {
        initialPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Location request timed out');
          },
        );

        print(
          '[LOCATION] Initial position: ${initialPosition.latitude}, ${initialPosition.longitude}',
        );

        // Update alert with initial dispatcher location (alert already accepted)
        await FirebaseFirestore.instance
            .collection('emergency_alerts')
            .doc(alertId)
            .update({
              'dispatcherLocation': GeoPoint(
                initialPosition.latitude,
                initialPosition.longitude,
              ),
              'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
            });

        print('[LOCATION] Initial location written');
        _lastSharedPosition = initialPosition;
      } catch (locationError) {
        print('[LOCATION ERROR] Failed to get initial position: $locationError');
        // Try with lower accuracy as fallback
        try {
          initialPosition = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(const Duration(seconds: 5));

          print('[LOCATION] Fallback position obtained: ${initialPosition.latitude}, ${initialPosition.longitude}');

          await FirebaseFirestore.instance
              .collection('emergency_alerts')
              .doc(alertId)
              .update({
                'dispatcherLocation': GeoPoint(
                  initialPosition.latitude,
                  initialPosition.longitude,
                ),
                'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
              });

          _lastSharedPosition = initialPosition;
        } catch (fallbackError) {
          print('[LOCATION ERROR] Fallback also failed: $fallbackError');
          // Continue without initial position - stream will provide updates
          print('[LOCATION] No initial position available, waiting for stream updates');
        }
      }

      // Start stream (web doesn't honor distanceFilter, so we manually check)
      _alertLocationStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((position) async {
            if (_activeAlertId != alertId || _alertDestination == null) return;

            try {
              // step 1 Check geofence first (using cached destination, no firestore read)
              final distanceToDestination = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                _alertDestination!.latitude,
                _alertDestination!.longitude,
              );

              print(
                '[GEOFENCE] Distance to destination: ${distanceToDestination.toStringAsFixed(1)}m',
              );

              // If within 50m geofence, mark as arrived (no need to update location)
              if (distanceToDestination <= 50) {
                print('[AUTO-ARRIVAL] Within 50m geofence, checking status...');

                // Fetch alert ONLY to verify status is still active
                final alertDoc = await FirebaseFirestore.instance
                    .collection('emergency_alerts')
                    .doc(alertId)
                    .get();

                if (!alertDoc.exists) {
                  print('[WARN] Alert document no longer exists');
                  return;
                }

                final status = alertDoc.data()?['status'] as String?;

                if (status == EmergencyAlert.STATUS_ACTIVE) {
                  print(
                    '[AUTO-ARRIVAL] Status is active, marking as arrived...',
                  );
                  await FirebaseFirestore.instance
                      .collection('emergency_alerts')
                      .doc(alertId)
                      .update({
                        'status': EmergencyAlert.STATUS_ARRIVED,
                        'arrivedAt': FieldValue.serverTimestamp(),
                        'dispatcherLocation': GeoPoint(
                          position.latitude,
                          position.longitude,
                        ),
                        'dispatcherLocationUpdatedAt':
                            FieldValue.serverTimestamp(),
                      });
                  print('[AUTO-ARRIVAL] Successfully marked as arrived');

                  // Clear cached destination to stop geofence checks
                  _alertDestination = null;
                  return;
                } else {
                  print('[SKIP GEOFENCE] Status is not active: $status');
                  return; // Don't update location if already arrived/resolved
                }
              }

              // step 2 Not within geofence, apply distance filter for location updates
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

              // step 3 Moved 5m+, update dispatcher location in Firestore
              print(
                '[UPDATE] Position: ${position.latitude}, ${position.longitude}',
              );
              _lastSharedPosition = position;

              await FirebaseFirestore.instance
                  .collection('emergency_alerts')
                  .doc(alertId)
                  .update({
                    'dispatcherLocation': GeoPoint(
                      position.latitude,
                      position.longitude,
                    ),
                    'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
                  });

              print('[LOCATION] Written to Firestore');
            } catch (e) {
              print('[ERROR] Location update failed: $e');
            }
          }, onError: (error) {
            // Handle location stream errors (iOS kCLErrorDomain, etc.)
            print('[LOCATION STREAM ERROR] $error');
            // Don't crash - location updates will retry automatically
            // Common errors: kCLErrorLocationUnknown (iOS can't get location)
          }, onDone: () {
            print('[LOCATION STREAM] Stream ended');
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

  void _handleFacilityTap(FacilityPin f) async {
    // Check if current user can delete this facility
    final user = FirebaseAuth.instance.currentUser;
    final canDelete =
        f.source == 'manual' &&
        f.meta?['addedBy'] != null &&
        f.meta?['addedBy'] == user?.uid;

    // Show details for the saved facility
    showModalBottomSheet(
      context: context,
      builder: (_) => FacilityDetailsSheet(
        facility: f,
        userLocation: userLocation,
        onNavigate: () {
          Navigator.pop(context); // Close the sheet
          _navigateToFacility(f);
        },
        canDelete: canDelete,
        onDelete: canDelete ? () => _deleteFacility(f) : null,
      ),
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

  Future<void> _deleteFacility(FacilityPin facility) async {
    try {
      // Delete from Firestore
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(facility.id)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully deleted ${facility.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete facility: $e'),
            backgroundColor: Colors.red,
          ),
        );
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

          final services =
              (data['services'] as List?)?.map((s) => s.toString()).toList() ??
              [];

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

  /// Search for facility and highlight it on map
  void _searchAndHighlightFacility(String query) {
    if (query.isEmpty) {
      setState(() => _highlightedFacilityId = null);
      return;
    }

    // Get all facilities from the current stream
    // We'll need to search through StreamBuilder data, so for now we'll do basic search
    // This method will be called from within the StreamBuilder context where we have facilities
    debugPrint('[Search] Searching for: $query');
    setState(() {
      _facilitySearchQuery = query;
    });
  }

  /// Show facility filter bottom sheet
  void _showFacilityFilterDialog({List<FacilityPin>? facilities}) {
    final allFacilities = facilities ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_list, color: Colors.white),
                      const SizedBox(width: 12),
                      const Text(
                        'Filter Facilities',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedFacilityTypes = {
                              'hospital',
                              'clinic',
                              'police station',
                              'fire station',
                              'shelter',
                            };
                            _showAllFacilities = true;
                            _facilitySearchQuery = '';
                            _highlightedFacilityId = null;
                          });
                          setModalState(() {});
                        },
                        child: const Text(
                          'Reset',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search facilities...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _facilitySearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _facilitySearchQuery = '';
                                  _highlightedFacilityId = null;
                                });
                                setModalState(() {});
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (value) {
                      // Find matching facility
                      if (value.isNotEmpty && allFacilities.isNotEmpty) {
                        final query = value.toLowerCase();
                        final matchedFacility = allFacilities.firstWhere((
                          facility,
                        ) {
                          final address =
                              facility.meta?['address'] as String? ?? '';
                          return facility.name.toLowerCase().contains(query) ||
                              address.toLowerCase().contains(query) ||
                              facility.type.toLowerCase().contains(query);
                        }, orElse: () => allFacilities.first);

                        setState(() {
                          _highlightedFacilityId = matchedFacility.id;
                          _facilitySearchQuery = value;
                        });
                      }
                      Navigator.pop(context); // Close the filter dialog
                    },
                    onChanged: (value) {
                      setState(() {
                        _facilitySearchQuery = value;
                      });
                      setModalState(() {});
                    },
                  ),
                ),

                // Show/Hide All Toggle
                SwitchListTile(
                  title: const Text('Show Facilities'),
                  subtitle: Text(
                    _showAllFacilities ? 'Visible on map' : 'Hidden from map',
                  ),
                  value: _showAllFacilities,
                  onChanged: (value) {
                    setState(() {
                      _showAllFacilities = value;
                    });
                    setModalState(() {});
                  },
                ),

                if (_showAllFacilities) ...[
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Facility Types',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Facility type chips
                  _buildFilterChip(
                    'hospital',
                    'Hospital 🏥',
                    Colors.red,
                    setModalState,
                  ),
                  _buildFilterChip(
                    'clinic',
                    'Clinic 💊',
                    Colors.pink,
                    setModalState,
                  ),
                  _buildFilterChip(
                    'police station',
                    'Police 👮',
                    Colors.blue,
                    setModalState,
                  ),
                  _buildFilterChip(
                    'fire station',
                    'Fire 🚒',
                    Colors.orange,
                    setModalState,
                  ),
                  _buildFilterChip(
                    'shelter',
                    'Shelter 🏠',
                    Colors.green,
                    setModalState,
                  ),
                ],

                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(
    String type,
    String label,
    Color color,
    Function setModalState,
  ) {
    final isSelected = _selectedFacilityTypes.contains(type);

    return CheckboxListTile(
      title: Text(label),
      value: isSelected,
      activeColor: color,
      onChanged: (value) {
        setState(() {
          if (value == true) {
            _selectedFacilityTypes.add(type);
          } else {
            _selectedFacilityTypes.remove(type);
          }
        });
        setModalState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentPageIndex != 0
          ? AppBar(
              title: Text(_getPageTitle()),
              actions: _currentPageIndex == 1
                  ? [
                      // Show filter icon on Map tab
                      IconButton(
                        icon: const Icon(Icons.filter_list),
                        tooltip: 'Filter Facilities',
                        onPressed: () => _showFacilityFilterDialog(
                          facilities: _currentFacilities,
                        ),
                      ),
                    ]
                  : null,
            )
          : null,
      body: StreamBuilder<QuerySnapshot>(
        // Listen to facilities
        stream: FirebaseFirestore.instance.collection('facilities').snapshots(),
        builder: (context, facilitiesSnapshot) {
          final manualPins = (facilitiesSnapshot.hasData)
              ? _pinsFromSnapshot(facilitiesSnapshot.data!)
              : const <FacilityPin>[];

          // Merge manual and Google Places facilities
          final allPins = [...manualPins, ...googlePlacesPins];

          // Store facilities for filter dialog
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _currentFacilities.length != allPins.length) {
              setState(() {
                _currentFacilities = allPins;
              });
            }
          });

          // Nested StreamBuilder for emergency alerts
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('emergency_alerts')
                .where(
                  'status',
                  whereIn: [
                    EmergencyAlert.STATUS_PENDING,
                    EmergencyAlert.STATUS_ACTIVE,
                    EmergencyAlert.STATUS_ARRIVED,
                  ],
                )
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

                  // Tab 2: Analytics
                  const AnalyticsDashboard(),

                  // Tab 3: Settings
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
        type: BottomNavigationBarType.fixed, // Needed for 4+ items
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Analytics',
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
        return 'Analytics';
      case 3:
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
    return Stack(
      children: [
        MapView(
          controller: _mapController,
          enableTap: _addMode,
          onMapTap: _handleMapTap,
          facilities: allPins,
          onFacilityTap: _handleFacilityTap,
          emergencyAlerts: alerts,
          onEmergencyAlertTap: _handleEmergencyAlertTap,
          followUserLocation: false,
          routePolyline: currentRoute,
          debugMode: _debugMode,
          selectedFacilityTypes: _selectedFacilityTypes,
          showAllFacilities: _showAllFacilities,
          highlightedFacilityId: _highlightedFacilityId,
        ),

        // Notification Permission Banner
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: NotificationPermissionBanner(),
        ),

        // ETA Display (when navigating)
        if (currentRouteInfo != null)
          ETADisplay(
            routeInfo: currentRouteInfo,
            destinationName: _getNavigationDestinationName(alerts),
            onCancel: clearRoute,
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
      ],
    );
  }

  /// Get the destination name for navigation display
  String _getNavigationDestinationName(List<EmergencyAlert> alerts) {
    if (_activeAlertId != null &&
        destinationLat != null &&
        destinationLon != null) {
      // Check if navigating to active alert
      final activeAlert = alerts
          .where((a) => a.id == _activeAlertId)
          .firstOrNull;
      if (activeAlert != null) {
        return 'SOS Alert - ${activeAlert.userEmail}';
      }
    }
    return 'Destination';
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
