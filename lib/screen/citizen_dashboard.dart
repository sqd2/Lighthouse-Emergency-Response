import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import '../widgets/map_view.dart';
import '../widgets/sos_widgets.dart';
import '../widgets/facility_details_widget.dart';
import '../widgets/notification_permission_banner.dart';
import '../widgets/medical_info_banner.dart';
import '../widgets/citizen_side_panel.dart';
import '../widgets/incoming_call_dialog.dart';
import '../widgets/eta_display.dart';
import '../models/facility_pin.dart';
import '../models/emergency_alert.dart';
import '../models/call.dart';
import '../mixins/route_navigation_mixin.dart';
import '../mixins/location_tracking_mixin.dart';
import '../services/notification_service.dart';
import '../services/medical_info_service.dart';
import '../services/places_service.dart';
import '../services/directions_service.dart';
import 'citizen_settings_screen.dart';

class CitizenDashboard extends StatefulWidget {
  const CitizenDashboard({super.key});

  @override
  State<CitizenDashboard> createState() => _CitizenDashboardState();
}

class _CitizenDashboardState extends State<CitizenDashboard>
    with RouteNavigationMixin, LocationTrackingMixin {
  // Map controller
  final _mapController = MapViewController();

  // Dispatcher tracking
  Polyline? _dispatcherRoute;
  GeoPoint? _lastDispatcherLocation; // Track last known dispatcher location
  DateTime? _lastRouteCalculation; // Track when we last calculated route

  // Throttling settings to reduce API calls
  static const Duration _routeUpdateThrottle = Duration(seconds: 30);
  static const double _minimumDistanceForRecalculation = 100.0; // meters

  // Medical info tracking
  bool _hasMedicalInfo = false;
  bool _medicalInfoChecked = false;

  // Debug mode: when true, shows pins, alerts, debug HUD, and logs
  bool _debugMode = false;

  // Call listener
  StreamSubscription<QuerySnapshot>? _callListener;

  // Tab navigation (no PageView - full screen tabs)
  int _currentPageIndex = 1; // Start on Map tab

  // Facility filtering state
  Set<String> _selectedFacilityTypes = {'hospital', 'clinic', 'police station', 'fire station', 'shelter'};
  bool _showAllFacilities = true;
  String? _highlightedFacilityId;
  String _facilitySearchQuery = '';
  List<FacilityPin> _currentFacilities = []; // Store for filter dialog

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
    _setupCallListener();
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

  Future<void> _setUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    // Load debugMode if it exists
    if (doc.exists && mounted) {
      setState(() {
        _debugMode = doc.data()?['debugMode'] ?? false;
      });
    }

    // Set role
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
      'role': 'citizen',
      'email': user.email,
    }, SetOptions(merge: true));
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
    _callListener?.cancel();
    super.dispose();
  }

  void _onBottomNavTap(int index) {
    setState(() {
      _currentPageIndex = index;
    });
  }

  Widget _buildNavBarItem(IconData icon, String label, int index) {
    final isSelected = _currentPageIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onBottomNavTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.red : Colors.grey,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.red : Colors.grey,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
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
      barrierColor: Colors.black54, // Add semi-transparent barrier to block map interaction
      isDismissible: true,
      enableDrag: true,
      builder: (context) => SOSSheet(userLocation: userLocation),
    );
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
                    color: Colors.blue,
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
                            _selectedFacilityTypes = {'hospital', 'clinic', 'police station', 'fire station', 'shelter'};
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
                        final matchedFacility = allFacilities.firstWhere(
                          (facility) {
                            final address = facility.meta?['address'] as String? ?? '';
                            return facility.name.toLowerCase().contains(query) ||
                                address.toLowerCase().contains(query) ||
                                facility.type.toLowerCase().contains(query);
                          },
                          orElse: () => allFacilities.first,
                        );

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
                  subtitle: Text(_showAllFacilities ? 'Visible on map' : 'Hidden from map'),
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
                  _buildFilterChip('hospital', 'Hospital 🏥', Colors.red, setModalState),
                  _buildFilterChip('clinic', 'Clinic 💊', Colors.pink, setModalState),
                  _buildFilterChip('police station', 'Police 👮', Colors.blue, setModalState),
                  _buildFilterChip('fire station', 'Fire 🚒', Colors.orange, setModalState),
                  _buildFilterChip('shelter', 'Shelter 🏠', Colors.green, setModalState),
                ],

                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String type, String label, Color color, Function setModalState) {
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
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: _currentPageIndex != 0 ? AppBar(
        title: Text(_getPageTitle()),
        actions: _currentPageIndex == 1 ? [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter Facilities',
            onPressed: () => _showFacilityFilterDialog(facilities: _currentFacilities),
          ),
        ] : null,
      ) : null,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('facilities').snapshots(),
        builder: (context, facilitiesSnapshot) {
          final manualPins = (facilitiesSnapshot.hasData)
              ? _pinsFromSnapshot(facilitiesSnapshot.data!)
              : const <FacilityPin>[];

          // Merge manual and Google Places facilities
          final allPins = [...manualPins, ...googlePlacesPins];

          // Store current facilities for filter dialog
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _currentFacilities = allPins;
            }
          });

          // Check for active SOS alerts by current user
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('emergency_alerts')
                .where('userId', isEqualTo: user?.uid ?? '')
                .where('status', whereIn: [
                  EmergencyAlert.STATUS_PENDING,
                  EmergencyAlert.STATUS_ACTIVE,
                  EmergencyAlert.STATUS_ARRIVED,
                ])
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
                  // Calculate distance moved
                  final distanceMoved = _lastDispatcherLocation != null
                      ? Geolocator.distanceBetween(
                          _lastDispatcherLocation!.latitude,
                          _lastDispatcherLocation!.longitude,
                          dispatcherLoc.latitude,
                          dispatcherLoc.longitude,
                        )
                      : double.infinity; // First update, always recalculate

                  // Check throttling - has enough time passed since last calculation?
                  final now = DateTime.now();
                  final timeSinceLastCalc = _lastRouteCalculation != null
                      ? now.difference(_lastRouteCalculation!)
                      : const Duration(days: 1); // First update, always recalculate

                  final shouldRecalculate = distanceMoved >= _minimumDistanceForRecalculation &&
                      timeSinceLastCalc >= _routeUpdateThrottle;

                  if (shouldRecalculate) {
                    print('====================================');
                    print('[ROUTE UPDATE] Dispatcher moved significantly');
                    print('  Previous: ${_lastDispatcherLocation?.latitude}, ${_lastDispatcherLocation?.longitude}');
                    print('  Current:  ${dispatcherLoc.latitude}, ${dispatcherLoc.longitude}');
                    print('  Distance moved: ${distanceMoved.toStringAsFixed(1)}m');
                    print('  Time since last calc: ${timeSinceLastCalc.inSeconds}s');
                    print('  Recalculating route...');
                    print('====================================');

                    _lastDispatcherLocation = dispatcherLoc;
                    _lastRouteCalculation = now;

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _updateDispatcherRoute(dispatcherLoc, alertLoc);
                    });
                  } else {
                    // Log why we skipped
                    if (distanceMoved < _minimumDistanceForRecalculation) {
                      print('[ROUTE SKIP] Distance too small: ${distanceMoved.toStringAsFixed(1)}m (min: $_minimumDistanceForRecalculation m)');
                    }
                    if (timeSinceLastCalc < _routeUpdateThrottle) {
                      print('[ROUTE SKIP] Too soon since last calc: ${timeSinceLastCalc.inSeconds}s (min: ${_routeUpdateThrottle.inSeconds}s)');
                    }

                    // Still update marker position even if we don't recalculate route
                    _lastDispatcherLocation = dispatcherLoc;
                  }
                }
              } else {
                // Clear dispatcher tracking when no active alert or no dispatcher location
                if (_dispatcherRoute != null || _lastDispatcherLocation != null || _lastRouteCalculation != null) {
                  print('[CLEANUP] Clearing dispatcher route and location tracking');
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _dispatcherRoute = null;
                        _lastDispatcherLocation = null;
                        _lastRouteCalculation = null;
                      });
                    }
                  });
                }
              }

              // Full-screen tab navigation (no PageView, no gesture conflicts)
              return IndexedStack(
                index: _currentPageIndex,
                children: [
                  // Tab 0: My Alerts
                  _buildMyAlertsPage(),

                  // Tab 1: Map (Full Screen)
                  _buildMapPage(
                    allPins,
                    hasActiveAlert,
                    activeAlert,
                    alertData,
                    dispatcherLocation,
                    dispatcherName,
                  ),

                  // Tab 2: Settings
                  CitizenSettingsScreen(
                    debugMode: _debugMode,
                    onDebugModeToggle: _toggleDebugMode,
                  ),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        elevation: 8,
        child: SizedBox(
          height: 65,
          child: Row(
            children: [
              const SizedBox(width: 20), // Left padding
              _buildNavBarItem(Icons.history, 'Alerts', 0),
              _buildNavBarItem(Icons.map, 'Map', 1),
              const SizedBox(width: 120), // Space for centered FAB with notch
              _buildNavBarItem(Icons.settings, 'Settings', 2),
              const SizedBox(width: 20), // Right padding
            ],
          ),
        ),
      ),
      floatingActionButton: SizedBox(
        width: 80,
        height: 80,
        child: FloatingActionButton(
          onPressed: _showSOSDialog,
          backgroundColor: Colors.red,
          elevation: 8,
          child: const Icon(Icons.sos, size: 48, color: Colors.white),
          tooltip: 'Send Emergency SOS',
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  String _getPageTitle() {
    switch (_currentPageIndex) {
      case 0:
        return 'My Alerts';
      case 1:
        return 'Map';
      case 2:
        return 'Settings';
      default:
        return 'Citizen Dashboard';
    }
  }

  Widget _buildMyAlertsPage() {
    // Full-screen version of CitizenSidePanel (no width constraint)
    return Container(
      color: Colors.grey[100],
      child: CitizenSidePanel(userLocation: userLocation),
    );
  }

  Widget _buildMapPage(
    List<FacilityPin> allPins,
    bool hasActiveAlert,
    DocumentSnapshot? activeAlert,
    Map<String, dynamic>? alertData,
    LatLng? dispatcherLocation,
    String? dispatcherName,
  ) {
    return Stack(
      children: [
        MapView(
          facilities: allPins,
          onFacilityTap: _handleFacilityTap,
          routePolyline: _dispatcherRoute ?? currentRoute,
          dispatcherLocation: dispatcherLocation,
          dispatcherName: dispatcherName,
          debugMode: _debugMode,
          // Disable marker taps when overlays are present to prevent click-through
          disableMarkerTaps: hasActiveAlert || (_medicalInfoChecked && !_hasMedicalInfo && !hasActiveAlert),
          controller: _mapController,
          selectedFacilityTypes: _selectedFacilityTypes,
          showAllFacilities: _showAllFacilities,
          highlightedFacilityId: _highlightedFacilityId,
        ),

        // Active SOS Alert Banner - with solid background to prevent click-through
        if (hasActiveAlert)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white, // SOLID background is KEY to preventing click-through
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ActiveSOSBanner(
                alertId: activeAlert!.id,
                alertData: alertData ?? {},
              ),
            ),
          ),

        // Notification Permission Banner (ALWAYS ON TOP)
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: NotificationPermissionBanner(),
        ),

        // ETA Display (when navigating to facility)
        if (currentRouteInfo != null && !hasActiveAlert)
          ETADisplay(
            routeInfo: currentRouteInfo,
            destinationName: destinationName ?? 'Facility',
            onCancel: clearRoute,
          ),

        // Recenter button (bottom-left)
        Positioned(
          bottom: 16,
          left: 16,
          child: FloatingActionButton(
            heroTag: 'recenter',
            onPressed: () => _mapController.recenterOnUserLocation(),
            backgroundColor: Colors.blue,
            child: const Icon(Icons.my_location),
          ),
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
  }
}
