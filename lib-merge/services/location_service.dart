import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static Future<Position> getCurrentPosition() async {
    // Solicitar permisos
    final status = await Permission.location.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Permiso de ubicación denegado');
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Servicios de ubicación deshabilitados');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permiso de ubicación denegado');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Permiso de ubicación denegado permanentemente');
    }

    // Obtener posición con alta precisión
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: const Duration(seconds: 10),
    );
  }
}
