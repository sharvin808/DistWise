import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:latlong2/latlong.dart';
import 'package:distwise/services/location_service.dart';
import 'package:distwise/services/route_service.dart';
import 'package:distwise/services/storage_service.dart';
import 'package:distwise/services/train_service.dart';
import 'package:distwise/services/network_service.dart';

// Entry point for the background service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  // Initialize Network Cache for background
  await NetworkService().init();
  
  // Initialize services
  final storageService = StorageService();
  final routeService = RouteService();
  final locationService = LocationService();
  final trainService = TrainService();
  
  // Handler for stopping the service
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
  
  // Setup Timer for 5 minute updates
  // We trigger immediately then every 5 mins
  _performUpdate(service, locationService, routeService, storageService, trainService);
  
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    if (await FlutterBackgroundService().isRunning() == false) timer.cancel();
    _performUpdate(service, locationService, routeService, storageService, trainService);
  });
}

Future<void> _performUpdate(
    ServiceInstance service,
    LocationService locationService,
    RouteService routeService,
    StorageService storageService,
    TrainService trainService) async {

  try {
     // 1. Get Current Location
     final position = await locationService.getCurrentPosition();
     final currentLatLng = LatLng(position.latitude, position.longitude);
     
     // 2. Get Destination & Mode
     final destination = await storageService.getDestination();
     final travelMode = await storageService.getTravelMode();
     String? stationName;
     
     if (travelMode == 'train') {
       stationName = await trainService.getNearestStation(currentLatLng);
     }
     
     if (destination == null) {
       if (service is AndroidServiceInstance) {
         service.setForegroundNotificationInfo(
           title: "DistWise Active",
           content: "No destination set.",
         );
       }
       return; 
     }

     double remainingDistance = 0.0;
     bool isOffline = false;
     
     // 3. Calculate Distance
     try {
       if (travelMode == 'train') {
         remainingDistance = await locationService.getDistanceInMeters(
           currentLatLng.latitude, currentLatLng.longitude,
           destination.latitude, destination.longitude
         );
       } else {
         // Try Online First
         final routeData = await routeService.getRoute(currentLatLng, destination);
         remainingDistance = routeData.distanceMeters;
         // Cache it
         await storageService.saveRoute(routeData);
       }
     } catch (e) {
       // Online failed, try Offline
       isOffline = true;
       final cachedRoute = await storageService.getCachedRoute();
       if (cachedRoute != null) {
         remainingDistance = RouteUtils.calculateRemainingDistance(currentLatLng, cachedRoute.points);
       } else {
         // Fallback if no cache (straight line?) or just error
         remainingDistance = await locationService.getDistanceInMeters(
            currentLatLng.latitude, currentLatLng.longitude,
            destination.latitude, destination.longitude
         );
       }
     }
     
     // 4. Update Notification
     String distString = (remainingDistance / 1000).toStringAsFixed(2) + " km";
     String content = "Remaining: $distString ${isOffline ? '(Offline)' : ''}";
     if (stationName != null) {
       content = "Reached: $stationName | $content";
     }
     
     if (service is AndroidServiceInstance) {
       service.setForegroundNotificationInfo(
         title: "Location: ${currentLatLng.latitude.toStringAsFixed(4)}, ${currentLatLng.longitude.toStringAsFixed(4)}",
         content: content,
       );
     }
     
     // Send data to UI if listening
     service.invoke(
       'update',
       {
         "lat": currentLatLng.latitude,
         "lng": currentLatLng.longitude,
         "distance": distString,
         "offline": isOffline,
         "station": stationName,
       },
     );
     
  } catch (e) {
    print("Background Error: $e");
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  // Required for iOS Background Fetch (if used)
  return true;
}

class BackgroundServiceManager {
  Future<void> initialize() async {
    final service = FlutterBackgroundService();
    
    // Create the notification channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'my_foreground', // id
      'MY FOREGROUND SERVICE', // title
      description: 'This channel is used for important notifications.', // description
      importance: Importance.low, 
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'my_foreground',
        initialNotificationTitle: 'DistWise Service',
        initialNotificationContent: 'Preparing...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }
  
  Future<void> start() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      service.startService();
    }
  }

  Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke("stopService"); 
  }
}
