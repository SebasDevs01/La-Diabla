// lib/features/addresses/presentation/screens/map_picker_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/maps_service.dart';
import '../../../../domain/entities/address_entity.dart';
import '../../../addresses/providers/addresses_provider.dart';
import '../../../auth/providers/auth_notifier.dart';

class MapPickerScreen extends ConsumerStatefulWidget {
  const MapPickerScreen({super.key});

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  final _mapsService = MapsService();
  final _locationService = LocationService();
  final _searchController = TextEditingController();
  final _referenceController = TextEditingController();
  final _mapCompleter = Completer<GoogleMapController>();

  LatLng _currentCenter = MapsService.defaultLocation;
  String _currentAddress = 'Buscando tu ubicación...';
  bool _isGeocoding = false;
  bool _isLoadingLocation = true;
  bool _isSaving = false;
  List<PlacePrediction> _predictions = [];
  AddressLabel _selectedLabel = AddressLabel.home;
  Timer? _geocodeTimer;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _geocodeTimer?.cancel();
    _searchController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final position = await _locationService.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);
      _currentCenter = latLng;
      final controller = await _mapCompleter.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: MapsService.userLocationZoom),
        ),
      );
      await _reverseGeocode(latLng);
    } catch (_) {
      // Permisos denegados: usar Bogotá como default
      await _reverseGeocode(_currentCenter);
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    if (mounted) setState(() => _isGeocoding = true);
    final address = await _mapsService.reverseGeocode(pos);
    if (mounted) {
      setState(() {
        _currentAddress = address;
        _isGeocoding = false;
      });
    }
  }

  void _onCameraMove(CameraPosition position) {
    _currentCenter = position.target;
  }

  void _onCameraIdle() {
    // Debounce: esperar 600ms antes de geocodificar
    _geocodeTimer?.cancel();
    _geocodeTimer = Timer(const Duration(milliseconds: 600), () {
      _reverseGeocode(_currentCenter);
    });
  }

  void _onSearchChanged() {
    final q = _searchController.text;
    if (q.length < 3) {
      setState(() => _predictions = []);
      return;
    }
    _geocodeTimer?.cancel();
    _geocodeTimer = Timer(const Duration(milliseconds: 500), () async {
      final results = await _mapsService.searchPlaces(q);
      if (mounted) setState(() => _predictions = results);
    });
  }

  Future<void> _selectPrediction(PlacePrediction prediction) async {
    _searchController.clear();
    setState(() {
      _predictions = [];
      _currentAddress = prediction.description;
      _isGeocoding = true;
    });
    FocusScope.of(context).unfocus();

    final latLng = await _mapsService.getPlaceLatLng(prediction.placeId);
    if (latLng != null && mounted) {
      _currentCenter = latLng;
      final controller = await _mapCompleter.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: MapsService.userLocationZoom),
        ),
      );
    }
    if (mounted) setState(() => _isGeocoding = false);
  }

  Future<void> _confirmAddress() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final user = ref.read(authNotifierProvider).user;
    final finalAddressText = (_currentAddress.trim().isEmpty || _currentAddress == 'Buscando tu ubicación...')
        ? 'Ubicación seleccionada'
        : _currentAddress;

    final address = AddressEntity(
      id: const Uuid().v4(),
      userId: user?.id ?? 'guest',
      label: _selectedLabel,
      formattedAddress: finalAddressText,
      latitude: _currentCenter.latitude,
      longitude: _currentCenter.longitude,
      reference: _referenceController.text.trim().isEmpty
          ? null
          : _referenceController.text.trim(),
      isDefault: false,
    );

    try {
      await ref.read(addressesProvider.notifier).addAddress(address);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Error al guardar la dirección. Intenta de nuevo.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ─── MAPA ──────────────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: MapsService.defaultLocation,
              zoom: MapsService.defaultZoom,
            ),
            onMapCreated: _mapCompleter.complete,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // ─── PIN FIJO EN EL CENTRO ─────────────────────────────────────────
          Center(
            child: Padding(
              // El pin "cae" sobre el punto, así que subimos el ícono medio pin
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withAlpha(100),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.location_on, color: Colors.white, size: 22),
                  ),
                  // Sombra del pin
                  Container(
                    width: 12,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── BARRA DE BÚSQUEDA SUPERIOR ────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Header con botón atrás
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
                        ),
                        child: const Icon(Icons.arrow_back, size: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Buscar dirección...',
                            prefixIcon: Icon(Icons.search, color: AppColors.primary),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Predicciones de Places
                if (_predictions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4, left: 50),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _predictions.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = _predictions[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 18),
                          title: Text(p.description, style: const TextStyle(fontSize: 13)),
                          onTap: () => _selectPrediction(p),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ─── BOTÓN MI UBICACIÓN ─────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 260,
            child: FloatingActionButton.small(
              heroTag: 'myLocation',
              backgroundColor: Colors.white,
              onPressed: _initLocation,
              child: _isLoadingLocation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.my_location, color: AppColors.primary),
            ),
          ),

          // ─── PANEL INFERIOR ────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Indicador de arrastre
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Dirección detectada
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.location_on, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _isGeocoding
                            ? Row(
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('Detectando dirección...', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                                ],
                              )
                            : Text(
                                _currentAddress,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Selector de etiqueta
                  Row(
                    children: AddressLabel.values.map((label) {
                      final selected = _selectedLabel == label;
                      final icon = label == AddressLabel.home
                          ? Icons.home_outlined
                          : label == AddressLabel.work
                              ? Icons.work_outline
                              : Icons.place_outlined;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedLabel = label),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primary : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 16, color: selected ? Colors.white : Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  label.displayName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? Colors.white : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // Referencia adicional
                  TextField(
                    controller: _referenceController,
                    decoration: InputDecoration(
                      hintText: 'Referencia (ej: piso 3, portón azul)',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      prefixIcon: const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Botón Confirmar
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_isGeocoding || _isSaving) ? null : _confirmAddress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Confirmar dirección',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  ),
);
  }
}


