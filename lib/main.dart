import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screen/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Set your Mapbox token once
  MapboxOptions.setAccessToken(
    "pk.eyJ1Ijoic2RzcSIsImEiOiJjbWc1YzhmanIwMzlsMmxvZWFtOXEzZHljIn0.Qqztf9X9n1oOzjBN2BJmwQ",
  );

  runApp(const LighthouseApp());
}

class LighthouseApp extends StatelessWidget {
  const LighthouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lighthouse',
      home: MapScreen(), // start with the map
    );
  }
}
