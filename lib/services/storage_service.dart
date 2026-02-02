import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'route_service.dart';

class StorageService {
  static const String KEY_DESTINATION_LAT = 'dest_lat';
  static const String KEY_DESTINATION_LNG = 'dest_lng';
  static const String KEY_CACHED_ROUTE = 'cached_route';
  static const String KEY_TRAVEL_MODE = 'travel_mode';

  Future<void> saveDestination(LatLng destination) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(KEY_DESTINATION_LAT, destination.latitude);
    await prefs.setDouble(KEY_DESTINATION_LNG, destination.longitude);
  }

  Future<LatLng?> getDestination() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(KEY_DESTINATION_LAT);
    final lng = prefs.getDouble(KEY_DESTINATION_LNG);
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
    return null;
  }

  Future<void> saveRoute(RouteData route) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_CACHED_ROUTE, json.encode(route.toJson()));
  }

  Future<RouteData?> getCachedRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(KEY_CACHED_ROUTE);
    if (jsonStr != null) {
      return RouteData.fromJson(json.decode(jsonStr));
    }
    return null;
  }
  
  Future<void> clearDestination() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(KEY_DESTINATION_LAT);
      await prefs.remove(KEY_DESTINATION_LNG);
      await prefs.remove(KEY_CACHED_ROUTE);
  }

  Future<void> saveTravelMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_TRAVEL_MODE, mode);
  }

  Future<String> getTravelMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(KEY_TRAVEL_MODE) ?? 'car';
  }
}
