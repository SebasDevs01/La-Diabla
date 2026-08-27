// lib/core/services/maps_service.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:geocoding/geocoding.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// Servicio de Google Maps — geocodificación, cálculo de distancias y rutas inteligentes.
class MapsService {
  final Logger _logger = Logger();

  static const String _mapsApiKey = 'AIzaSyB4ANVQZbyq0oKQba0aZcAuLU3pR26Gaxo';

  // ─── Cocina Central La Diabla (Calle 59 # 39W-24, Estoraques 1 / Mutis, Bucaramanga) ───
  static const LatLng defaultLocation = LatLng(7.092758, -73.142590);
  static const String kitchenAddress = 'Cl. 59 # 39W-24, Barrio Estoraques 1, Comuna 17 Mutis, Bucaramanga';
  static const double defaultZoom = 15.5;
  static const double userLocationZoom = 16.5;

  // ─── CameraPosition ───────────────────────────────────────────────────────
  CameraPosition get defaultCameraPosition => const CameraPosition(
        target: defaultLocation,
        zoom: defaultZoom,
      );

  CameraPosition cameraPositionFor(LatLng position, {double? zoom}) =>
      CameraPosition(target: position, zoom: zoom ?? defaultZoom);

  // ─── Cálculo Geodésico de Distancia Real (Fórmula Haversine en KM) ────────
  static double calculateDistanceKm(LatLng start, LatLng end) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        math.cos((end.latitude - start.latitude) * p) / 2 +
        math.cos(start.latitude * p) *
            math.cos(end.latitude * p) *
            (1 - math.cos((end.longitude - start.longitude) * p)) /
            2;
    final km = 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
    return double.parse(km.toStringAsFixed(1));
  }

  /// Calcula la distancia desde la cocina central hasta la ubicación destino.
  static double distanceFromKitchenKm(LatLng destination) {
    return calculateDistanceKm(defaultLocation, destination);
  }

  /// Tiempo estimado de entrega en moto según distancia.
  static String estimateDeliveryTime(double distanceKm) {
    if (distanceKm <= 2.5) return '15 - 25 min';
    if (distanceKm <= 5.0) return '25 - 35 min';
    if (distanceKm <= 8.0) return '35 - 45 min';
    return '45 - 60 min';
  }

  // ─── Geocodificación Inversa (coordenadas → dirección) ────────────────────
  Future<String> reverseGeocode(LatLng position) async {
    try {
      final placemarks = await geo.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) return 'Ubicación seleccionada';

      final p = placemarks.first;
      final parts = <String>[];

      if (p.street != null && p.street!.isNotEmpty) parts.add(p.street!);
      if (p.subLocality != null && p.subLocality!.isNotEmpty) {
        parts.add(p.subLocality!);
      }
      if (p.locality != null && p.locality!.isNotEmpty) parts.add(p.locality!);

      return parts.isNotEmpty ? parts.join(', ') : 'Ubicación seleccionada';
    } catch (e) {
      _logger.w('reverseGeocode error: $e');
      return 'Ubicación seleccionada';
    }
  }

  // ─── Places Autocomplete ─────────────────────────────────────────────────
  Future<List<PlacePrediction>> searchPlaces(String query) async {
    if (query.trim().length < 3) return [];
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': query,
          'key': _mapsApiKey,
          'language': 'es',
          'components': 'country:co',
          'types': 'address',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return [];

      final predictions = data['predictions'] as List<dynamic>;
      return predictions
          .map((p) => PlacePrediction(
                placeId: p['place_id'] as String,
                description: p['description'] as String,
              ))
          .toList();
    } catch (e) {
      _logger.e('searchPlaces error: $e');
      return [];
    }
  }

  Future<LatLng?> getPlaceLatLng(String placeId) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {
          'place_id': placeId,
          'key': _mapsApiKey,
          'fields': 'geometry',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;

      final loc = data['result']['geometry']['location'] as Map<String, dynamic>;
      return LatLng(loc['lat'] as double, loc['lng'] as double);
    } catch (e) {
      _logger.e('getPlaceLatLng error: $e');
      return null;
    }
  }

  // ─── Google Directions API (Ruta Óptima por Calles Reales) ───────────────
  Future<List<LatLng>> getDirectionsRoute(LatLng origin, LatLng destination) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/directions/json',
        {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'key': _mapsApiKey,
          'mode': 'driving',
          'language': 'es',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK' && (data['routes'] as List).isNotEmpty) {
          final points = data['routes'][0]['overview_polyline']['points'] as String;
          return _decodePolyline(points);
        }
      }
    } catch (e) {
      _logger.w('Directions API error: $e');
    }
    // Fallback a línea directa si no hay red
    return [origin, destination];
  }

  /// Decodificador de string de polilínea codificada de Google Maps
  static List<LatLng> _decodePolyline(String encoded) {
    final poly = <LatLng>[];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  // ─── Estimación de Tarifa de Entrega ─────────────────────────────────────
  double estimateDeliveryFee(double distanceKm) {
    if (distanceKm <= 2.5) return 3500;
    if (distanceKm <= 5.0) return 5000;
    if (distanceKm <= 8.0) return 7500;
    return 9500;
  }

  Marker createDeliveryMarker(LatLng position) => Marker(
        markerId: const MarkerId('delivery_location'),
        position: position,
        infoWindow: const InfoWindow(title: 'Dirección de entrega'),
      );

  // ─── Navegación Externa Oficial (Google Maps & Waze) ─────────────────────

  /// Abre la navegación hacia las coordenadas usando Google Maps oficial.
  static Future<bool> openInGoogleMaps(double lat, double lng, {String? label}) async {
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    try {
      if (await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Abre la navegación hacia las coordenadas usando Waze oficial.
  static Future<bool> openInWaze(double lat, double lng) async {
    final wazeAppUri = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
    final wazeWebFallback = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');

    try {
      // Intentar abrir la app nativa de Waze
      if (await canLaunchUrl(wazeAppUri)) {
        return await launchUrl(wazeAppUri, mode: LaunchMode.externalApplication);
      }
      // Fallback a Waze Web o Play Store / App Store
      return await launchUrl(wazeWebFallback, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        return await launchUrl(wazeWebFallback, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }
}

class PlacePrediction {
  const PlacePrediction({
    required this.placeId,
    required this.description,
    this.mainText,
    this.secondaryText,
  });

  final String placeId;
  final String description;
  final String? mainText;
  final String? secondaryText;
}
