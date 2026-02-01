import 'dart:async';
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
import 'package:geolocator/geolocator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LatLng? _currentPosition;
  LatLng? _destination;
  String _distanceDisplay = "N/A";
  bool _isServiceRunning = false;
  bool _isOffline = false;
  List<LatLng> _routePoints = [];
  
  final MapController _mapController = MapController();
  final BackgroundServiceManager _bgManager = BackgroundServiceManager();
  final StorageService _storageService = StorageService();
  final GeocodingService _geocodingService = GeocodingService();
  final RouteService _routeService = RouteService();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkLocationService();
    _requestPermissions();
    _loadState();
    _setupServiceListener();
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
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_off, color: Colors.orange),
              SizedBox(width: 10),
              Text('Location Disabled'),
            ],
          ),
          content: const Text(
            'Location services are currently disabled. Please enable location to use DistWise and track your journey.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                final opened = await LocationService().openLocationSettings();
                if (opened) {
                  // Wait a bit for user to enable location, then reload
                  await Future.delayed(const Duration(seconds: 2));
                  _loadState();
                }
              },
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.notification,
    ].request(); 
    
    // Also check for specific background location if needed
    if (await Permission.locationWhenInUse.isGranted) {
        // Just requesting always is tricky, usually need to explain to user.
        // For now rely on basic permissions.
    }
  }

  Future<void> _loadState() async {
    final dest = await _storageService.getDestination();
    final pos = await LocationService().getCurrentPosition();
    
    final isRunning = await FlutterBackgroundService().isRunning();
    
    setState(() {
      _destination = dest;
      _currentPosition = LatLng(pos.latitude, pos.longitude);
      _isServiceRunning = isRunning;
    });
    
    if (_currentPosition != null) {
      // Move map to current pos
      _mapController.move(_currentPosition!, 15);
    }
  }

  void _setupServiceListener() {
    FlutterBackgroundService().on('update').listen((event) {
      if (event != null) {
        setState(() {
          if (event['lat'] != null && event['lng'] != null) {
             _currentPosition = LatLng(event['lat'], event['lng']);
          }
          _distanceDisplay = event['distance'] ?? "N/A";
          _isOffline = event['offline'] ?? false;
        });
      }
    });
  }

  Future<void> _setDestination(LatLng point) async {
    setState(() {
      _destination = point;
    });
    await _storageService.saveDestination(point);
    await _calculateDistance();
  }
  
  Future<void> _calculateDistance() async {
    if (_currentPosition == null || _destination == null) {
      return;
    }
    
    try {
      final routeData = await _routeService.getRoute(_currentPosition!, _destination!);
      setState(() {
        _routePoints = routeData.points;
        _distanceDisplay = "${(routeData.distanceMeters / 1000).toStringAsFixed(2)} km";
      });
    } catch (e) {
      // Fallback to straight-line distance
      final distance = await LocationService().getDistanceInMeters(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _destination!.latitude,
        _destination!.longitude,
      );
      setState(() {
        _routePoints = [_currentPosition!, _destination!];
        _distanceDisplay = "${(distance / 1000).toStringAsFixed(2)} km (direct)";
      });
    }
  }
  
  Future<void> _searchAndSetDestination() async {
    final address = _searchController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a destination')),
      );
      return;
    }
    
    try {
      final coords = await _geocodingService.getCoordinatesFromAddress(address);
      if (coords != null) {
        await _setDestination(coords);
        _mapController.move(coords, 15);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Destination set to $address')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location not found. Please try again.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<void> _toggleService() async {
    if (_isServiceRunning) {
      await _bgManager.stop();
      setState(() {
        _isServiceRunning = false;
      });
    } else {
      if (_destination == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a destination first!')),
        );
        return;
      }
      await _bgManager.start();
      setState(() {
        _isServiceRunning = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DistWise'),
        actions: [
            Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Icon(
                    _isOffline ? Icons.wifi_off : Icons.wifi,
                    color: _isOffline ? Colors.red : Colors.green,
                ),
            )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          try {
            final pos = await LocationService().getCurrentPosition();
            final newPosition = LatLng(pos.latitude, pos.longitude);
            setState(() {
              _currentPosition = newPosition;
            });
            _mapController.move(newPosition, 15);
            if (_destination != null) {
              await _calculateDistance();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error getting location: ${e.toString()}')),
              );
            }
          }
        },
        child: const Icon(Icons.my_location),
        tooltip: 'My Location',
      ),
      body: Stack(
        children: [
          // Map layer (rendered first, at the bottom)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition ?? const LatLng(0, 0),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.distwise.app',
              ),
              // Route polyline
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 4.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
              // Markers
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.my_location, color: Colors.blue, size: 40),
                    ),
                  ],
                ),
               if (_destination != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _destination!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.flag, color: Colors.red, size: 40),
                    ),
                  ],
                ),
            ],
          ),
          // Search bar at the top (rendered on top of map)
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Enter destination address',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                        ),
                        onSubmitted: (_) => _searchAndSetDestination(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _searchAndSetDestination,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Control panel at the bottom (rendered on top of map)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isServiceRunning ? "Journey Active" : "Search to set destination",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Distance: $_distanceDisplay",
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _toggleService,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isServiceRunning ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_isServiceRunning ? "Stop Journey" : "Start Journey"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
