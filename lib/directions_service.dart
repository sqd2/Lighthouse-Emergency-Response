import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';

class DirectionsService {
  static const String _apiKey = 'AIzaSyCvvz3UmQXQR9PzRUeYlNu2wJqpxG8FvuQ';

  // Cloud Function URL for web to avoid CORS
  static const String _cloudFunctionUrl =
      'https://us-central1-lighthouse-2498c.cloudfunctions.net/getDirections';

  // CACHING TO PREVENT EXCESSIVE API CALLS
  static final Map<String, _CachedRoute> _routeCache = {};
  static const Duration _cacheExpiration = Duration(minutes: 5);

  // Round coordinates to ~100m precision (3 decimal places)
  // This prevents API calls for tiny movements
  static String _getCacheKey(double originLat, double originLng, double destLat, double destLng) {
    final oLat = originLat.toStringAsFixed(3);
    final oLng = originLng.toStringAsFixed(3);
    final dLat = destLat.toStringAsFixed(3);
    final dLng = destLng.toStringAsFixed(3);
    return '$oLat,$oLng->$dLat,$dLng';
  }

  /// Get route from origin to destination (with caching)
  static Future<RouteInfo?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    bool bypassCache = false,
  }) async {
    // Check cache first (unless bypassed)
    if (!bypassCache) {
      final cacheKey = _getCacheKey(originLat, originLng, destLat, destLng);
      final cached = _routeCache[cacheKey];

      if (cached != null && !cached.isExpired) {
        print('[CACHE HIT] Saved API call for route: $cacheKey');
        print('  Cache age: ${DateTime.now().difference(cached.timestamp).inSeconds}s');
        return cached.route;
      }

      if (cached != null && cached.isExpired) {
        print('[CACHE] Expired entry removed: $cacheKey');
        _routeCache.remove(cacheKey);
      }
    }

    // Use Cloud Function on web to avoid CORS, direct API on mobile
    print('[API CALL] Platform is ${kIsWeb ? 'web' : 'native'}');
    RouteInfo? route;

    if (kIsWeb) {
      print('DirectionsService: Using Cloud Function for web');
      route = await _getRouteViaCloudFunction(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
      );
    } else {
      print('DirectionsService: Using direct API for native');
      route = await _getRouteDirect(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
      );
    }

    // Cache the result
    if (route != null) {
      final cacheKey = _getCacheKey(originLat, originLng, destLat, destLng);
      _routeCache[cacheKey] = _CachedRoute(route);
      print('[CACHE] Stored route: $cacheKey (${_routeCache.length} total cached)');
    }

    return route;
  }

  /// Clear old cache entries (call periodically)
  static void clearExpiredCache() {
    _routeCache.removeWhere((key, value) => value.isExpired);
    print('[CACHE] Cleared expired entries. ${_routeCache.length} remaining.');
  }

  /// Clear all cache (useful for testing)
  static void clearAllCache() {
    _routeCache.clear();
    print('[CACHE] Cleared all entries.');
  }

  /// Direct API call for mobile platforms
  static Future<RouteInfo?> _getRouteDirect({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$originLat,$originLng'
      '&destination=$destLat,$destLng'
      '&key=$_apiKey',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return _parseDirectionsResponse(data);
      } else {
        print('HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching directions: $e');
      return null;
    }
  }

  /// Cloud Function call for web platform (avoids CORS)
  static Future<RouteInfo?> _getRouteViaCloudFunction({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    print('DirectionsService: Calling Cloud Function at $_cloudFunctionUrl');
    try {
      final requestBody = jsonEncode({
        'originLat': originLat,
        'originLng': originLng,
        'destLat': destLat,
        'destLng': destLng,
      });
      print('DirectionsService: Request body: $requestBody');

      final response = await http.post(
        Uri.parse(_cloudFunctionUrl),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      print('DirectionsService: Cloud Function response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('DirectionsService: Successfully received directions data');
        return _parseDirectionsResponse(data);
      } else {
        print('Cloud Function error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      print('Error fetching directions via Cloud Function: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Parse directions API response
  static RouteInfo? _parseDirectionsResponse(Map<String, dynamic> data) {
    try {
      if (data['status'] == 'OK' && data['routes'] != null && data['routes'].isNotEmpty) {
        final route = data['routes'][0];
        final leg = route['legs'][0];

        // Decode polyline
        final encodedPolyline = route['overview_polyline']['points'];
        print('DirectionsService: Encoded polyline length: ${encodedPolyline.length}');

        final polylinePoints = _decodePolyline(encodedPolyline);
        print('DirectionsService: Decoded ${polylinePoints.length} points');

        if (polylinePoints.isNotEmpty) {
          print('DirectionsService: First point: ${polylinePoints.first.latitude}, ${polylinePoints.first.longitude}');
          print('DirectionsService: Last point: ${polylinePoints.last.latitude}, ${polylinePoints.last.longitude}');
        }

        return RouteInfo(
          polylinePoints: polylinePoints,
          distance: leg['distance']['text'],
          duration: leg['duration']['text'],
          distanceMeters: leg['distance']['value'],
          durationSeconds: leg['duration']['value'],
        );
      } else {
        print('Directions API error: ${data['status']}');
        return null;
      }
    } catch (e, stackTrace) {
      print('Error parsing directions response: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Decode Google polyline encoding using proven package
  /// This package handles JavaScript compatibility correctly
  static List<LatLng> _decodePolyline(String encoded) {
    print('DirectionsService: Starting polyline decode, length: ${encoded.length}');

    try {
      // Use the google_polyline_algorithm package which handles JS compatibility
      final List<List<num>> decoded = decodePolyline(encoded);

      final points = decoded.map((point) {
        return LatLng(point[0].toDouble(), point[1].toDouble());
      }).toList();

      print('DirectionsService: Successfully decoded ${points.length} points');
      if (points.isNotEmpty) {
        print('DirectionsService: Sample points:');
        print('  Point 0: ${points[0].latitude}, ${points[0].longitude}');
        if (points.length > 1) {
          print('  Point 1: ${points[1].latitude}, ${points[1].longitude}');
        }
        if (points.length > 2) {
          print('  Point mid: ${points[points.length ~/ 2].latitude}, ${points[points.length ~/ 2].longitude}');
        }
        print('  Point last: ${points.last.latitude}, ${points.last.longitude}');
      }

      return points;
    } catch (e, stackTrace) {
      print('DirectionsService: Error decoding polyline: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }
}

class RouteInfo {
  final List<LatLng> polylinePoints;
  final String distance;
  final String duration;
  final int distanceMeters;
  final int durationSeconds;

  const RouteInfo({
    required this.polylinePoints,
    required this.distance,
    required this.duration,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

/// Internal cache entry for routes
class _CachedRoute {
  final RouteInfo route;
  final DateTime timestamp;

  _CachedRoute(this.route) : timestamp = DateTime.now();

  bool get isExpired {
    return DateTime.now().difference(timestamp) > DirectionsService._cacheExpiration;
  }
}
