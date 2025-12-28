import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';

/// Service responsible for fetching nearby emergency facilities from Google Places API.
///
/// This service provides location-based search for hospitals, police stations,
/// fire stations, and ambulance services. I have implemented caching to minimize
/// API calls and reduce costs while maintaining data freshness.
class PlacesService {
  /// Private constructor to prevent instantiation of this service class.
  PlacesService._();

  static const String _apiKey = ApiConfig.googleMapsApiKey;

  // Cloud Function URL for web to avoid CORS
  static const String _cloudFunctionUrl =
      'https://us-central1-lighthouse-2498c.cloudfunctions.net/searchNearbyPlaces';

  // CACHING TO PREVENT EXCESSIVE API CALLS
  static final Map<String, _CachedPlaces> _placesCache = {};
  static const Duration _cacheExpiration = Duration(minutes: 10);

  // Round coordinates to ~100m precision (3 decimal places)
  // This prevents API calls for tiny movements
  static String _getCacheKey(double lat, double lng, String type, int radius) {
    final roundedLat = lat.toStringAsFixed(3);
    final roundedLng = lng.toStringAsFixed(3);
    return '$roundedLat,$roundedLng:$type:$radius';
  }

  /// Calculate distance between two coordinates in meters using Haversine formula
  static double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0; // Earth radius in meters
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  /// Fetch all emergency facilities near the given location
  /// [radiusMeters] specifies the search radius (default: 2000m / 2km)
  static Future<List<GooglePlaceFacility>> getAllEmergencyFacilities(
    double lat,
    double lng, {
    int radiusMeters = 2000,
  }) async {
    final facilities = <GooglePlaceFacility>[];

    // Define emergency facility types with their mappings
    final facilityTypes = {
      'hospital': 'Hospital',
      'doctor': 'Clinic',
      'police': 'Police Station',
      'fire_station': 'Fire Station',
    };

    // OPTIMIZATION: Run all 4 API calls in PARALLEL instead of sequentially
    // This reduces total fetch time from ~4 seconds to ~1 second
    print('[PLACES] Fetching ${facilityTypes.length} facility types in parallel...');
    final startTime = DateTime.now();

    final futures = facilityTypes.entries.map((entry) async {
      try {
        final results = await _fetchNearbyPlaces(lat, lng, entry.key, radiusMeters);
        final typeFacilities = <GooglePlaceFacility>[];

        for (final place in results) {
          final facility = _parsePlaceToFacility(place, entry.value);

          // Double-check distance to ensure it's within radius
          final distance = calculateDistance(lat, lng, facility.lat, facility.lng);
          if (distance <= radiusMeters) {
            typeFacilities.add(facility);
          }
        }

        return typeFacilities;
      } catch (e) {
        print('Error fetching ${entry.key}: $e');
        return <GooglePlaceFacility>[];
      }
    }).toList();

    // Wait for all parallel API calls to complete
    final results = await Future.wait(futures);

    // Flatten all results into single list
    for (final typeResults in results) {
      facilities.addAll(typeResults);
    }

    final duration = DateTime.now().difference(startTime);
    print('[PLACES]  Fetched ${facilities.length} facilities in ${duration.inMilliseconds}ms');

    return facilities;
  }

  static Future<List<Map<String, dynamic>>> _fetchNearbyPlaces(
    double lat,
    double lng,
    String type,
    int radiusMeters,
  ) async {
    // Check cache first
    final cacheKey = _getCacheKey(lat, lng, type, radiusMeters);
    final cached = _placesCache[cacheKey];

    if (cached != null && !cached.isExpired) {
      print('[PLACES CACHE HIT] Saved API call for $type at $cacheKey');
      print('  Cache age: ${DateTime.now().difference(cached.timestamp).inSeconds}s');
      return cached.places;
    }

    if (cached != null && cached.isExpired) {
      print('[PLACES CACHE] Expired entry removed: $cacheKey');
      _placesCache.remove(cacheKey);
    }

    // Cache miss - fetch from API
    print('[PLACES API CALL] Fetching $type at $lat,$lng radius=$radiusMeters');
    List<Map<String, dynamic>> results;

    // Use Cloud Function on web to avoid CORS, direct API on mobile
    if (kIsWeb) {
      results = await _fetchNearbyPlacesViaCloudFunction(lat, lng, type, radiusMeters);
    } else {
      results = await _fetchNearbyPlacesDirect(lat, lng, type, radiusMeters);
    }

    // Cache the result
    _placesCache[cacheKey] = _CachedPlaces(results);
    print('[PLACES CACHE] Stored $type: $cacheKey (${_placesCache.length} total cached)');

    return results;
  }

  /// Direct API call for mobile platforms
  static Future<List<Map<String, dynamic>>> _fetchNearbyPlacesDirect(
    double lat,
    double lng,
    String type,
    int radiusMeters,
  ) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$radiusMeters&type=$type&key=$_apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['status'] == 'REQUEST_DENIED') {
        throw Exception('API Key Error: ${data['error_message']}');
      }

      final results = data['results'] as List? ?? [];
      return results.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch places: ${response.body}');
    }
  }

  /// Cloud Function call for web platform (avoids CORS)
  static Future<List<Map<String, dynamic>>> _fetchNearbyPlacesViaCloudFunction(
    double lat,
    double lng,
    String type,
    int radiusMeters,
  ) async {
    final response = await http.post(
      Uri.parse(_cloudFunctionUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'latitude': lat,
        'longitude': lng,
        'radius': radiusMeters,
        'type': type,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['status'] == 'REQUEST_DENIED' || data['error'] != null) {
        throw Exception('Cloud Function Error: ${data['message'] ?? data['error']}');
      }

      final results = data['results'] as List? ?? [];
      return results.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch places via Cloud Function: ${response.body}');
    }
  }

  static GooglePlaceFacility _parsePlaceToFacility(
    Map<String, dynamic> place,
    String category,
  ) {
    final geometry = place['geometry'] as Map<String, dynamic>? ?? {};
    final location = geometry['location'] as Map<String, dynamic>? ?? {};

    final lat = (location['lat'] as num?)?.toDouble() ?? 0.0;
    final lng = (location['lng'] as num?)?.toDouble() ?? 0.0;
    final name = place['name']?.toString() ?? 'Unknown';
    final placeId = place['place_id']?.toString() ?? '';
    final address = place['vicinity']?.toString() ?? '';
    final rating = (place['rating'] as num?)?.toDouble();
    final isOpen = place['opening_hours']?['open_now'] as bool?;
    final userRatingsTotal = place['user_ratings_total'] as int?;

    return GooglePlaceFacility(
      placeId: placeId,
      name: name,
      category: category,
      lat: lat,
      lng: lng,
      address: address,
      rating: rating,
      isOpenNow: isOpen,
      userRatingsTotal: userRatingsTotal,
    );
  }

  /// Fetch detailed information for a specific place
  static Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=name,formatted_address,formatted_phone_number,opening_hours,website,rating,user_ratings_total&key=$_apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'OK') {
        return data['result'] as Map<String, dynamic>?;
      }
    }
    return null;
  }

  /// Clear old cache entries (call periodically)
  static void clearExpiredCache() {
    _placesCache.removeWhere((key, value) => value.isExpired);
    print('[PLACES CACHE] Cleared expired entries. ${_placesCache.length} remaining.');
  }

  /// Clear all cache (useful for testing)
  static void clearAllCache() {
    _placesCache.clear();
    print('[PLACES CACHE] Cleared all entries.');
  }
}

/// Model for Google Places facility
class GooglePlaceFacility {
  final String placeId;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final String address;
  final double? rating;
  final bool? isOpenNow;
  final int? userRatingsTotal;

  const GooglePlaceFacility({
    required this.placeId,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.address,
    this.rating,
    this.isOpenNow,
    this.userRatingsTotal,
  });
}

/// Internal cache entry for places
class _CachedPlaces {
  final List<Map<String, dynamic>> places;
  final DateTime timestamp;

  _CachedPlaces(this.places) : timestamp = DateTime.now();

  bool get isExpired {
    return DateTime.now().difference(timestamp) > PlacesService._cacheExpiration;
  }
}
