import 'package:flutter_compass/flutter_compass.dart';

class CompassService {
  Stream<CompassEvent>? get compassStream => FlutterCompass.events;
}
