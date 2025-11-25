/// Lightweight model for facilities rendered on the map.
class FacilityPin {
  final String id;
  final String name;
  final String type; // 'hospital', 'clinic', 'police', 'firestation', etc.
  final double lon;
  final double lat;
  final Map<String, dynamic>? meta;
  final String source; // 'manual' or 'google_places'

  const FacilityPin({
    required this.id,
    required this.name,
    required this.type,
    required this.lon,
    required this.lat,
    this.meta,
    this.source = 'manual',
  });

  /// Create a FacilityPin from a Google Places facility
  factory FacilityPin.fromGooglePlace(dynamic googlePlace) {
    return FacilityPin(
      id: googlePlace.placeId,
      name: googlePlace.name,
      type: googlePlace.category,
      lon: googlePlace.lng,
      lat: googlePlace.lat,
      source: 'google_places',
      meta: {
        'address': googlePlace.address,
        'rating': googlePlace.rating,
        'isOpenNow': googlePlace.isOpenNow,
        'userRatingsTotal': googlePlace.userRatingsTotal,
        'placeId': googlePlace.placeId,
      },
    );
  }
}
