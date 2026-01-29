import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';

class GeocodingService {
  /// Convert an address or place name to coordinates
  Future<LatLng?> getCoordinatesFromAddress(String address) async {
    if (address.trim().isEmpty) {
      return null;
    }
    
    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final location = locations.first;
        return LatLng(location.latitude, location.longitude);
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
