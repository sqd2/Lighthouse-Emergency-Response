import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../directions_service.dart';
import '../places_service.dart';

/// Mixin that provides route navigation functionality
/// Can be used by both citizen and dispatcher dashboards
mixin RouteNavigationMixin<T extends StatefulWidget> on State<T> {
  // Route navigation state
  Polyline? _currentRoute;
  RouteInfo? _currentRouteInfo;
  double? _destinationLat;
  double? _destinationLon;
  String? _destinationName;
  Position? _lastRouteUpdatePosition;

  // Route tracking thresholds
  static const double _offRouteThresholdMeters = 50.0;
  static const double _minDistanceForRouteUpdateMeters = 20.0;

  // Getters for accessing route state
  Polyline? get currentRoute => _currentRoute;
  RouteInfo? get currentRouteInfo => _currentRouteInfo;
  double? get destinationLat => _destinationLat;
  double? get destinationLon => _destinationLon;
  String? get destinationName => _destinationName;

  /// Calculate and display a route to the given destination
  Future<void> navigateToLocation({
    required BuildContext context,
    required Position userLocation,
    required double destLat,
    required double destLng,
    String? locationName,
  }) async {
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
    print('Origin: ${userLocation.latitude}, ${userLocation.longitude}');
    print('Destination: $destLat, $destLng');

    final route = await DirectionsService.getRoute(
      originLat: userLocation.latitude,
      originLng: userLocation.longitude,
      destLat: destLat,
      destLng: destLng,
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

    // Validate we have enough points
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
      _destinationLat = destLat;
      _destinationLon = destLng;
      _destinationName = locationName;
      _lastRouteUpdatePosition = userLocation;
      _currentRoute = Polyline(
        polylineId: PolylineId(
          'route_${DateTime.now().millisecondsSinceEpoch}',
        ),
        points: route.polylinePoints,
        color: Colors.blue,
        width: kIsWeb ? 6 : 5,
        geodesic: !kIsWeb,
        visible: true,
      );
    });

    print('Polyline created and set in state');
    print('===== ROUTE CALCULATION END =====');

    // Close any open bottom sheets
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

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
          onPressed: clearRoute,
        ),
      ),
    );
  }

  /// Clear the current route
  void clearRoute() {
    setState(() {
      _currentRoute = null;
      _currentRouteInfo = null;
      _destinationLat = null;
      _destinationLon = null;
      _destinationName = null;
      _lastRouteUpdatePosition = null;
    });
  }

  /// Update route based on user's current position
  Future<void> updateRouteProgress(
    BuildContext context,
    Position currentPosition,
  ) async {
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
      clearRoute();
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
}
