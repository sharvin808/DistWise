import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path/path.dart';
import 'package:latlong2/latlong.dart';

class DatabaseService {
  static sqflite.Database? _database;

  Future<sqflite.Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<sqflite.Database> _initDatabase() async {
    final dbPath = await sqflite.getDatabasesPath();
    final path = join(dbPath, 'distwise.db');

    return await sqflite.openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE stations (
            id TEXT PRIMARY KEY,
            name TEXT,
            lat REAL,
            lng REAL,
            timestamp INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE search_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            query TEXT UNIQUE,
            lat REAL,
            lng REAL,
            timestamp INTEGER
          )
        ''');
      },
    );
  }

  Future<void> saveStation(String id, String name, LatLng position) async {
    final db = await database;
    await db.insert(
      'stations',
      {
        'id': id,
        'name': name,
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getNearestStationOffline(LatLng position) async {
    final db = await database;
    // Simple heuristic: get stations in a roughly 5km box and sort by distance in memory
    final double range = 0.05; // approx 5km
    final List<Map<String, dynamic>> maps = await db.query(
      'stations',
      where: 'lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?',
      whereArgs: [
        position.latitude - range,
        position.latitude + range,
        position.longitude - range,
        position.longitude + range,
      ],
    );

    if (maps.isEmpty) return null;

    // Sort by actual distance
    final Distance distance = const Distance();
    Map<String, dynamic>? closest;
    double minDistance = double.infinity;

    for (var m in maps) {
      final d = distance.as(LengthUnit.Meter, position, LatLng(m['lat'], m['lng']));
      if (d < minDistance) {
        minDistance = d;
        closest = m;
      }
    }

    return closest;
  }

  Future<void> saveSearch(String query, LatLng position) async {
    final db = await database;
    await db.insert(
      'search_history',
      {
        'query': query.toLowerCase(),
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<LatLng?> getSearchOffline(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'search_history',
      where: 'query = ?',
      whereArgs: [query.toLowerCase()],
    );

    if (maps.isNotEmpty) {
      return LatLng(maps.first['lat'], maps.first['lng']);
    }
    return null;
  }
}
