// API Keys Configuration
// IMPORTANT: This file is ignored by git. Never commit actual API keys!
// Copy this file to api_keys.dart and add your actual keys there.

class ApiKeys {
  // Google Maps API Key (if you add maps in the future)
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY_HERE';
  
  // OpenStreetMap/Nominatim API (currently using free public service)
  // If you upgrade to a paid service, add your key here
  static const String nominatimApiKey = '';
  
  // OSRM Routing (currently using free public service)
  // If you upgrade to a private instance, add the URL here
  static const String osrmBaseUrl = 'http://router.project-osrm.org/route/v1/driving';
  
  // Add any other API keys your app needs
  static const String customApiKey = 'YOUR_API_KEY_HERE';
}
