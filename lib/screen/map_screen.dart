import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart' as geo;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  mapbox.MapboxMap? _mapboxMap;
  late mapbox.CircleAnnotationManager _circleManager;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled;
    geo.LocationPermission permission;

    // Check if GPS is enabled
    serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enable location services")),
      );
      return;
    }

    // Check permission
    permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) {
        return;
      }
    }

    if (permission == geo.LocationPermission.deniedForever) {
      return;
    }

    // Start tracking
    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((geo.Position position) async {
      if (_mapboxMap != null) {
        final coords = mapbox.Position(position.longitude, position.latitude);

        // Move camera to user location
        _mapboxMap!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: coords),
            zoom: 15.0,
          ),
          mapbox.MapAnimationOptions(duration: 1000),
        );

        // Add/update blue circle
        if (_circleManager != null) {
          _circleManager.deleteAll(); // remove old marker
          await _circleManager.create(
            mapbox.CircleAnnotationOptions(
              geometry: mapbox.Point(coordinates: coords),
              circleRadius: 8.0,
              circleColor: 0xFF0000FF, // Blue
              circleOpacity: 0.8,
              circleStrokeWidth: 2.0,
              circleStrokeColor: 0xFFFFFFFF, // White border
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("mapbox with gps")),
      body: mapbox.MapWidget(
        styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
        cameraOptions: mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(101.6869, 3.1390), // Default KL
          ),
          zoom: 12.0,
        ),
        onMapCreated: (map) async {
          _mapboxMap = map;
          // Create CircleAnnotationManager for user dot
          final annotationManager = await _mapboxMap!.annotations
              .createCircleAnnotationManager();
          _circleManager = annotationManager;
        },
      ),
    );
  }
}
