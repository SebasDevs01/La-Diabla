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

  /// Calcula el rumbo (bearing) en grados (0 - 360) entre dos puntos para orientar la moto.
  static double calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * (math.pi / 180.0);
    final lon1 = start.longitude * (math.pi / 180.0);
    final lat2 = end.latitude * (math.pi / 180.0);
    final lon2 = end.longitude * (math.pi / 180.0);

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final radians = math.atan2(y, x);
    return (radians * (180.0 / math.pi) + 360.0) % 360.0;
  }

  /// Calcula la distancia total compuesta de entrega:
  /// Tramo 1: Repartidor -> Cocina Central
  /// Tramo 2: Cocina Central -> Cliente
  static ({double storeDistanceKm, double deliveryDistanceKm, double totalDistanceKm})
      calculateCompositeDistance({
    required LatLng driverLocation,
    LatLng storeLocation = defaultLocation,
    required LatLng customerLocation,
  }) {
    final storeDist = calculateDistanceKm(driverLocation, storeLocation);
    final deliveryDist = calculateDistanceKm(storeLocation, customerLocation);
    final total = double.parse((storeDist + deliveryDist).toStringAsFixed(1));
    return (
      storeDistanceKm: storeDist,
      deliveryDistanceKm: deliveryDist,
      totalDistanceKm: total,
    );
  }

  /// Calcula la distancia desde la cocina central hasta la ubicación destino.
  static double distanceFromKitchenKm(LatLng destination) {
    return calculateDistanceKm(defaultLocation, destination);
  }

  /// Tiempo estimado de entrega en moto según distancia.
  static String estimateDeliveryTime(double distanceKm, {double speedKmh = 35.0}) {
    final minutes = (distanceKm / speedKmh * 60).round() + 10; // +10 min preparación/despacho
    if (minutes <= 25) return '$minutes - ${minutes + 10} min';
    return '$minutes - ${minutes + 15} min';
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

  // ─── Rutas Inteligentes por Calles Reales (OSRM + Google Maps Fallback) ───
  Future<RouteResult> getRouteDetails(LatLng origin, LatLng destination) async {
    // 1º Intentar OSRM (Open Source Routing Machine) — Especializado en ruteo por calles sin cuota
    try {
      final osrmUri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(osrmUri).timeout(const Duration(seconds: 7));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['code'] == 'Ok' && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'] as Map<String, dynamic>;
          final coords = geometry['coordinates'] as List<dynamic>;

          final points = coords.map((c) {
            final lng = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();

          final distanceMeters = (route['distance'] as num?)?.toDouble() ?? 0.0;
          final durationSeconds = (route['duration'] as num?)?.toDouble() ?? 0.0;

          final distanceKm = double.parse((distanceMeters / 1000.0).toStringAsFixed(1));
          final durationMinutes = (durationSeconds / 60.0).round();

          if (points.length >= 2) {
            return RouteResult(
              points: points,
              distanceKm: distanceKm > 0 ? distanceKm : calculateDistanceKm(origin, destination),
              durationMinutes: durationMinutes > 0 ? durationMinutes : 15,
            );
          }
        }
      }
    } catch (e) {
      _logger.w('OSRM Directions error: $e');
    }

    // 2º Fallback a Google Directions API si está habilitada
    try {
      final gUri = Uri.https(
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

      final response = await http.get(gUri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK' && (data['routes'] as List).isNotEmpty) {
          final points = data['routes'][0]['overview_polyline']['points'] as String;
          final decoded = _decodePolyline(points);
          final dist = calculateDistanceKm(origin, destination);
          return RouteResult(
            points: decoded,
            distanceKm: dist,
            durationMinutes: (dist / 30.0 * 60).round() + 5,
          );
        }
      }
    } catch (e) {
      _logger.w('Google Directions API error: $e');
    }

    // 3º Fallback geodésico
    final directDist = calculateDistanceKm(origin, destination);
    return RouteResult(
      points: [origin, destination],
      distanceKm: directDist,
      durationMinutes: (directDist / 30.0 * 60).round() + 10,
    );
  }

  /// Obtiene los puntos de la ruta inteligente trazada sobre las calles
  Future<List<LatLng>> getDirectionsRoute(LatLng origin, LatLng destination) async {
    final result = await getRouteDetails(origin, destination);
    return result.points;
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

  // ─── Tarifa Dinámica de Entrega por Distancia (Bucaramanga y Área Metro) ───
  static double calculateDeliveryFee(double distanceKm) {
    if (distanceKm <= 2.5) {
      return 4500.0; // Mutis, Estoraques, Real de Minas, etc.
    } else if (distanceKm <= 5.0) {
      return 6500.0; // Centro, Cabecera, San Francisco, Ciudadela
    } else if (distanceKm <= 8.0) {
      return 9000.0; // Provenza, Morrorrico, Floridablanca norte
    } else if (distanceKm <= 12.0) {
      return 12500.0; // Cañaveral, Girón, Ruitoque bajo
    } else {
      final extraKm = (distanceKm - 12.0).ceil();
      return 12500.0 + (extraKm * 1500.0); // Piedecuesta / periferia
    }
  }

  double estimateDeliveryFee(double distanceKm) => calculateDeliveryFee(distanceKm);

  Marker createDeliveryMarker(LatLng position) => Marker(
        markerId: const MarkerId('delivery_location'),
        position: position,
        infoWindow: const InfoWindow(title: 'Dirección de entrega'),
      );

  // ─── Navegación Externa Oficial (Google Maps & Waze) ─────────────────────

  /// Abre Google Maps nativo (app). Evita abrir en el navegador web usando esquemas nativos.
  static Future<bool> openInGoogleMaps(double lat, double lng, {String? label}) async {
    // 1º Android: Esquema nativo de navegación paso a paso en app
    final androidNavUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    try {
      if (await canLaunchUrl(androidNavUri)) {
        return await launchUrl(androidNavUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    // 2º Android: Esquema geo universal para Maps app
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng${label != null ? '($label)' : ''}');
    try {
      if (await canLaunchUrl(geoUri)) {
        return await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    // 3º iOS: Esquema nativo de Google Maps para iOS
    final iosMapsUri = Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');
    try {
      if (await canLaunchUrl(iosMapsUri)) {
        return await launchUrl(iosMapsUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    // 4º Fallback final: URL web externa
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    try {
      return await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Abre Waze nativo (prioridad absoluta). Fallback a app de Google Maps si Waze no está instalado.
  static Future<bool> openInWaze(double lat, double lng) async {
    // 1º App nativa de Waze
    final wazeUri = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
    try {
      if (await canLaunchUrl(wazeUri)) {
        return await launchUrl(wazeUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    // 2º Fallback directo a Google Maps App nativa
    return await openInGoogleMaps(lat, lng, label: 'La Diabla Entrega');
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

class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
  });

  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;
}

