import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteService {
  final String _baseUrl = 'http://router.project-osrm.org/route/v1/driving';

  Future<RouteData> getRoute(LatLng start, LatLng end) async {
    final url = '$_baseUrl/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';
    
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final distance = (route['distance'] as num).toDouble(); // meters
          final geometry = route['geometry'];
          final coordinates = (geometry['coordinates'] as List)
              .map((point) => LatLng(point[1], point[0]))
              .toList();

          return RouteData(distanceMeters: distance, points: coordinates);
        }
      }
      throw Exception('No route found');
    } catch (e) {
      throw Exception('Failed to fetch route: $e');
    }
  }
}

class RouteData {
  final double distanceMeters;
  final List<LatLng> points;

  RouteData({required this.distanceMeters, required this.points});
  
  Map<String, dynamic> toJson() {
    return {
      'distanceMeters': distanceMeters,
      'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    };
  }

  factory RouteData.fromJson(Map<String, dynamic> json) {
    return RouteData(
      distanceMeters: json['distanceMeters'],
      points: (json['points'] as List).map((p) => LatLng(p['lat'], p['lng'])).toList(),
    );
  }
}

class RouteUtils {
  static double calculateRemainingDistance(LatLng currentPos, List<LatLng> routePoints) {
    if (routePoints.isEmpty) return 0.0;

    // Find the closest point index
    int closestIndex = 0;
    double minDistance = double.infinity;
    final Distance distanceCalculator = const Distance();

    for (int i = 0; i < routePoints.length; i++) {
      final d = distanceCalculator.as(LengthUnit.Meter, currentPos, routePoints[i]);
      if (d < minDistance) {
        minDistance = d;
        closestIndex = i;
      }
    }

    // Sum distance from closest index to end
    double remaining = 0.0;
    for (int i = closestIndex; i < routePoints.length - 1; i++) {
        remaining += distanceCalculator.as(LengthUnit.Meter, routePoints[i], routePoints[i+1]);
    }
    
    // Add distance from currentPos to the closest point (optional, but more accurate to just assume on-track)
    // For "remaining driving distance", usually summing from the closest road point is best.
    
    return remaining;
  }
}
