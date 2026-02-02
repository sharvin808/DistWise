import 'package:distwise/services/database_service.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';

class GeocodingService {
  final DatabaseService _db = DatabaseService();

  /// Convert an address or place name to coordinates
  Future<LatLng?> getCoordinatesFromAddress(String address) async {
    final query = address.trim();
    if (query.isEmpty) {
      return null;
    }
    
    // 1. Try local database first
    final offlineResult = await _db.getSearchOffline(query);
    if (offlineResult != null) return offlineResult;

    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final location = locations.first;
        final coords = LatLng(location.latitude, location.longitude);
        
        // 2. Save result for future offline use
        await _db.saveSearch(query, coords);
        return coords;
      }
      return null;
    } catch (e) {
      print('Geocoding error: $e');
      return null;
    }
  }
  
  /// Get a place name from coordinates (reverse geocoding)
  Future<String?> getAddressFromCoordinates(LatLng coords) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        coords.latitude,
        coords.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return '${place.street}, ${place.locality}, ${place.country}';
      }
      return null;
    } catch (e) {
      print('Reverse geocoding error: $e');
      return null;
    }
  }
}
