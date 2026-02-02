import 'package:distwise/services/network_service.dart';
import 'package:distwise/services/database_service.dart';
import 'package:latlong2/latlong.dart';

class TrainService {
  final DatabaseService _db = DatabaseService();

  /// Fetches the nearest railway station name within a 3km radius
  Future<String?> getNearestStation(LatLng position) async {
    final lat = position.latitude;
    final lon = position.longitude;
    
    // 1. Try to fetch from local database first (if we have it within range)
    final offlineStation = await _db.getNearestStationOffline(position);
    if (offlineStation != null) {
      return offlineStation['name'];
    }

    // 2. Overpass API query
    final query = '[out:json];node["railway"="station"](around:3000,$lat,$lon);out;';
    final url = 'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}';

    try {
      final response = await NetworkService().dio.get(url);
      
      if (response.statusCode == 200) {
        final data = response.data;
        final elements = data['elements'] as List;
        
        if (elements.isNotEmpty) {
          // Sort by proximity
          elements.sort((a, b) {
            final distA = (a['lat'] - lat) * (a['lat'] - lat) + (a['lon'] - lon) * (a['lon'] - lon);
            final distB = (b['lat'] - lat) * (b['lat'] - lat) + (b['lon'] - lon) * (b['lon'] - lon);
            return distA.compareTo(distB);
          });
          
          final closest = elements.first;
          final tags = closest['tags'];
          if (tags != null) {
             final name = tags['name'] ?? tags['name:en'] ?? 'Unnamed Station';
             
             // 3. Save to local database for future offline use
             await _db.saveStation(
               closest['id'].toString(), 
               name, 
               LatLng(closest['lat'], closest['lon'])
             );
             
             return name;
          }
        }
      }
    } catch (e) {
      print('Error fetching station: $e');
    }
    return null;
  }
}
