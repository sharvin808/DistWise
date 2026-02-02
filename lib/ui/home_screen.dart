import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:distwise/services/background_service.dart';
import 'package:distwise/services/storage_service.dart';
import 'package:distwise/services/location_service.dart';
import 'package:distwise/services/geocoding_service.dart';
import 'package:distwise/services/route_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:distwise/services/compass_service.dart';
import 'package:distwise/services/train_service.dart';
import 'package:distwise/services/network_service.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LatLng? _currentPosition;
  LatLng? _destination;
  String _distanceDisplay = "0.00 km";
  bool _isServiceRunning = false;
  bool _isOffline = false;
  List<LatLng> _routePoints = [];
  String _travelMode = 'car';
  String? _currentStation;
  bool _isStationLoading = false;
  
  final MapController _mapController = MapController();
  final BackgroundServiceManager _bgManager = BackgroundServiceManager();
  final StorageService _storageService = StorageService();
  final GeocodingService _geocodingService = GeocodingService();
  final RouteService _routeService = RouteService();
  final TrainService _trainService = TrainService();
  final TextEditingController _searchController = TextEditingController();
  final CompassService _compassService = CompassService();
  double? _heading;
  StreamSubscription<CompassEvent>? _compassSubscription;

  @override
  void initState() {
    super.initState();
    _checkLocationService();
    _requestPermissions();
    _loadState();
    _setupServiceListener();
    _setupCompass();
  }
  
  void _setupCompass() {
    _compassSubscription = _compassService.compassStream?.listen((event) {
      if (mounted) {
        setState(() {
          _heading = event.heading;
        });
      }
    });
  }
  
  Future<void> _checkLocationService() async {
    final isEnabled = await LocationService().isLocationServiceEnabled();
    if (!isEnabled && mounted) {
      _showLocationServiceDialog();
    }
  }
  
  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E293B).withOpacity(0.8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            title: Row(
              children: [
                const Icon(Icons.location_off, color: Color(0xFFEF4444)).animate().shake(),
                const SizedBox(width: 12),
                Text(
                  'Location Disabled',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Text(
              'Location services are currently disabled. Please enable location to use DistWise and track your journey.',
              style: GoogleFonts.inter(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final opened = await LocationService().openLocationSettings();
                  if (opened) {
                    await Future.delayed(const Duration(seconds: 2));
                    _loadState();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack);
      },
    );
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _compassSubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.notification,
    ].request(); 
  }

  Future<void> _refresh() async {
    // Clear search and reset UI state
    setState(() {
      _searchController.clear();
      _routePoints = [];
      _distanceDisplay = "0.00 km";
      _currentStation = null;
    });
    
    // Reload state (current position, destination, etc.)
    await _loadState();
    
    // Show a small feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location Refreshed', style: GoogleFonts.inter()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF6366F1),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _loadState() async {
    try {
      final dest = await _storageService.getDestination();
      final pos = await LocationService().getCurrentPosition();
      final isRunning = await FlutterBackgroundService().isRunning();
      final mode = await _storageService.getTravelMode();
      
      setState(() {
        _destination = dest;
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _isServiceRunning = isRunning;
        _travelMode = mode;
      });
      
      if (_currentPosition != null) {
        _mapController.move(_currentPosition!, 15);
        if (_destination != null) {
          _calculateDistance();
        }
      }
    } catch (e) {
      print("Error loading state: $e");
    }
  }

  void _setupServiceListener() {
    FlutterBackgroundService().on('update').listen((event) {
      if (event != null && mounted) {
        setState(() {
          if (event['lat'] != null && event['lng'] != null) {
             _currentPosition = LatLng(event['lat'], event['lng']);
             if (_travelMode == 'train') {
               if (event['station'] != null) {
                 _currentStation = event['station'];
               } else {
                 _checkNearestStation(_currentPosition!);
               }
             }
          }
          _distanceDisplay = event['distance'] ?? "0.00 km";
          _isOffline = event['offline'] ?? false;
        });
      }
    });
  }

  Future<void> _checkNearestStation(LatLng position) async {
    if (_isStationLoading) return;
    
    setState(() => _isStationLoading = true);
    try {
      final station = await _trainService.getNearestStation(position);
      if (mounted && station != null && station != _currentStation) {
        setState(() => _currentStation = station);
      }
    } finally {
      if (mounted) setState(() => _isStationLoading = false);
    }
  }

  void _toggleTravelMode(String mode) async {
    if (_travelMode == mode) return;
    
    setState(() {
      _travelMode = mode;
      if (mode == 'car') {
        _currentStation = null;
      } else if (_currentPosition != null) {
        _checkNearestStation(_currentPosition!);
      }
    });
    await _storageService.saveTravelMode(mode);
    if (_destination != null) {
      _calculateDistance();
    }
  }

  Future<void> _setDestination(LatLng point) async {
    setState(() {
      _destination = point;
    });
    await _storageService.saveDestination(point);
    await _calculateDistance();
  }
  
  Future<void> _calculateDistance() async {
    if (_currentPosition == null || _destination == null) return;
    
    if (_travelMode == 'train') {
      final distance = await LocationService().getDistanceInMeters(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _destination!.latitude,
        _destination!.longitude,
      );
      setState(() {
        _routePoints = [_currentPosition!, _destination!];
        _distanceDisplay = "${(distance / 1000).toStringAsFixed(2)} km";
      });
      return;
    }

    try {
      final routeData = await _routeService.getRoute(_currentPosition!, _destination!);
      setState(() {
        _routePoints = routeData.points;
        _distanceDisplay = "${(routeData.distanceMeters / 1000).toStringAsFixed(2)} km";
      });
    } catch (e) {
      final distance = await LocationService().getDistanceInMeters(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _destination!.latitude,
        _destination!.longitude,
      );
      setState(() {
        _routePoints = [_currentPosition!, _destination!];
        _distanceDisplay = "${(distance / 1000).toStringAsFixed(2)} km";
      });
    }
  }
  
  Future<void> _searchAndSetDestination() async {
    final address = _searchController.text.trim();
    if (address.isEmpty) {
      _showCustomSnackBar('Please enter a destination', isError: true);
      return;
    }
    
    try {
      final coords = await _geocodingService.getCoordinatesFromAddress(address);
      if (coords != null) {
        await _setDestination(coords);
        _mapController.move(coords, 15);
        _showCustomSnackBar('Destination set to $address');
      } else {
        _showCustomSnackBar('Location not found. Please try again.', isError: true);
      }
    } catch (e) {
      _showCustomSnackBar('Error: ${e.toString()}', isError: true);
    }
  }

  void _showCustomSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF6366F1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _toggleService() async {
    if (_isServiceRunning) {
      await _bgManager.stop();
      setState(() => _isServiceRunning = false);
    } else {
      if (_destination == null) {
        _showCustomSnackBar('Please select a destination first!', isError: true);
        return;
      }
      await _bgManager.start();
      setState(() => _isServiceRunning = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: const Color(0xFF0F172A).withOpacity(0.5),
              elevation: 0,
              centerTitle: true,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    height: 40,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DistWise',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      letterSpacing: 1.2,
                      foreground: Paint()
                        ..shader = const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                        ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
                    ),
                  ),
                ],
              ),
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isOffline ? const Color(0xFFEF4444).withOpacity(0.1) : const Color(0xFF10B981).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isOffline ? Icons.wifi_off : Icons.wifi,
                    color: _isOffline ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                    size: 20,
                  ),
                ).animate(onPlay: (controller) => controller.repeat())
                 .shimmer(duration: 2.seconds, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () async {
            try {
              final pos = await LocationService().getCurrentPosition();
              final newPosition = LatLng(pos.latitude, pos.longitude);
              setState(() => _currentPosition = newPosition);
              _mapController.move(newPosition, 15);
              if (_destination != null) await _calculateDistance();
            } catch (e) {
              _showCustomSnackBar('Error getting location: ${e.toString()}', isError: true);
            }
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.my_location, color: Colors.white),
        ),
      ).animate(onPlay: (controller) => controller.repeat(reverse: true))
       .scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05), duration: 1.seconds, curve: Curves.easeInOut),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition ?? const LatLng(0, 0),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.distwise.app',
                tileProvider: CachedTileProvider(
                  store: NetworkService().cacheStore,
                ),
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: const Color(0xFF6366F1),
                      gradientColors: [const Color(0xFF6366F1), const Color(0xFF06B6D4)],
                    ),
                  ],
                ),
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 60,
                      height: 60,
                      child: Transform.rotate(
                        angle: ((_heading ?? 0) * (3.14159 / 180) * -1),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.3),
                                shape: BoxShape.circle,
                              ),
                            ).animate(onPlay: (controller) => controller.repeat())
                             .scale(begin: const Offset(1, 1), end: const Offset(2, 2), duration: 2.seconds)
                             .fadeOut(duration: 2.seconds),
                            const Icon(Icons.navigation, color: Color(0xFF6366F1), size: 30),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
               if (_destination != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _destination!,
                      width: 50,
                      height: 50,
                      child: const Column(
                        children: [
                          Icon(Icons.location_on, color: Color(0xFFEF4444), size: 40),
                        ],
                      ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                       .moveY(begin: 0, end: -10, duration: 1.seconds, curve: Curves.easeInOut),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _toggleTravelMode('car'),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _travelMode == 'car' ? const Color(0xFF6366F1) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.all(4),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.directions_car, color: _travelMode == 'car' ? Colors.white : Colors.white54, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Car',
                                  style: GoogleFonts.inter(
                                    color: _travelMode == 'car' ? Colors.white : Colors.white54,
                                    fontWeight: _travelMode == 'car' ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _toggleTravelMode('train'),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _travelMode == 'train' ? const Color(0xFF6366F1) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.all(4),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.train, color: _travelMode == 'train' ? Colors.white : Colors.white54, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Train',
                                  style: GoogleFonts.inter(
                                    color: _travelMode == 'train' ? Colors.white : Colors.white54,
                                    fontWeight: _travelMode == 'train' ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0),
          Positioned(
            top: 165,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                    child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Color(0xFF6366F1), size: 20),
                          onPressed: _refresh,
                          tooltip: 'Refresh Location',
                        ),
                        // const Icon(Icons.search, color: Color(0xFF6366F1), size: 20),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: GoogleFonts.inter(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Where to go?',
                              hintStyle: GoogleFonts.inter(color: Colors.white38),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            ),
                            onSubmitted: (_) => _searchAndSetDestination(),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                            onPressed: () => setState(() => _searchController.clear()),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.1),
                        Colors.white.withOpacity(0.03),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_travelMode == 'train' && _currentStation != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.train, color: Color(0xFF6366F1), size: 16),
                            const SizedBox(width: 8),
                            Text(
                              "REACHED: ",
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF6366F1),
                                letterSpacing: 1,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _currentStation!.toUpperCase(),
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: Colors.white.withOpacity(0.1)),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isServiceRunning ? "ACTIVE JOURNEY" : "READY TO START",
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: _isServiceRunning ? const Color(0xFF10B981) : Colors.white54,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _distanceDisplay,
                                style: GoogleFonts.outfit(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (_isServiceRunning ? const Color(0xFF10B981) : const Color(0xFF6366F1)).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              _isServiceRunning ? (_travelMode == 'car' ? Icons.navigation : Icons.train) : Icons.map,
                              color: _isServiceRunning ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                              size: 30,
                            ),
                          ).animate(target: _isServiceRunning ? 1 : 0)
                           .shimmer(duration: 2.seconds),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _toggleService,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ).copyWith(
                            elevation: MaterialStateProperty.all(0),
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _isServiceRunning 
                                  ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                                  : [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isServiceRunning ? const Color(0xFFEF4444) : const Color(0xFF6366F1)).withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              child: Text(
                                _isServiceRunning ? "STOP JOURNEY" : "START JOURNEY",
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.2, end: 0),
        ],
      ),
    );
  }
}

