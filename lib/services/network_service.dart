import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:path/path.dart';

class NetworkService {
  late Dio _dio;
  late CacheStore _cacheStore;
  
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  
  NetworkService._internal();

  Future<void> init() async {
    final dir = await getTemporaryDirectory();
    final cacheDir = Directory(join(dir.path, 'dio_cache'));
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    
    _cacheStore = FileCacheStore(cacheDir.path);
    
    final cacheOptions = CacheOptions(
      store: _cacheStore,
      policy: CachePolicy.refreshForceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
    );

    _dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: cacheOptions));
  }

  Dio get dio => _dio;
  CacheStore get cacheStore => _cacheStore;
}
