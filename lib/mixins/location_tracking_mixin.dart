import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/facility_pin.dart';
import '../places_service.dart';

/// Mixin that provides location tracking and facility management
/// Can be used by both citizen and dispatcher dashboards
mixin LocationTrackingMixin<T extends StatefulWidget> on State<T> {
  // Location and facilities state
  Position? _userLocation;
  List<FacilityPin> _googlePlacesPins = [];
  bool _loadingGooglePlaces = false;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Constants
  static const int _searchRadiusMeters = 5000;
  static const double _refreshDistanceThreshold = 500.0;

  // Getters for accessing location state
  Position? get userLocation => _userLocation;
  List<FacilityPin> get googlePlacesPins => _googlePlacesPins;
  bool get loadingGooglePlaces => _loadingGooglePlaces;

  /// Initialize location tracking and fetch initial facilities
  Future<void> initializeLocationTracking({
    Function(Position)? onLocationUpdate,
  }) async {
    await _fetchUserLocationAndGooglePlaces();
    _startLocationTracking(onLocationUpdate: onLocationUpdate);
  }

  /// Clean up location tracking resources
  void disposeLocationTracking() {
    _positionStreamSubscription?.cancel();
  }

  /// Start continuous location tracking
  void _startLocationTracking({
    Function(Position)? onLocationUpdate,
  }) {
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
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
      } else {
        _userLocation = newPosition;
      }

      _userLocation = newPosition;

      // Call the optional callback for additional processing
      onLocationUpdate?.call(newPosition);
    });
  }

  /// Fetch initial user location and Google Places facilities
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

  /// Refresh facilities when user moves significantly
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
}
