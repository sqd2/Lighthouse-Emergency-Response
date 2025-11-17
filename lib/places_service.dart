import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class PlacesService {
  static const String _apiKey = 'AIzaSyCvvz3UmQXQR9PzRUeYlNu2wJqpxG8FvuQ';

  // Cloud Function URL for web to avoid CORS
  static const String _cloudFunctionUrl =
      'https://us-central1-lighthouse-2498c.cloudfunctions.net/searchNearbyPlaces';

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

    for (final entry in facilityTypes.entries) {
      try {
        final results = await _fetchNearbyPlaces(lat, lng, entry.key, radiusMeters);
        for (final place in results) {
          final facility = _parsePlaceToFacility(place, entry.value);

          // Double-check distance to ensure it's within radius
          final distance = calculateDistance(lat, lng, facility.lat, facility.lng);
          if (distance <= radiusMeters) {
            facilities.add(facility);
          }
        }
      } catch (e) {
        print('Error fetching ${entry.key}: $e');
      }
    }

    return facilities;
  }

  static Future<List<Map<String, dynamic>>> _fetchNearbyPlaces(
    double lat,
    double lng,
    String type,
    int radiusMeters,
  ) async {
    // Use Cloud Function on web to avoid CORS, direct API on mobile
    if (kIsWeb) {
      return _fetchNearbyPlacesViaCloudFunction(lat, lng, type, radiusMeters);
    } else {
      return _fetchNearbyPlacesDirect(lat, lng, type, radiusMeters);
    }
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
