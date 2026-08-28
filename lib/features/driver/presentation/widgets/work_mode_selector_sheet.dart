// lib/features/driver/presentation/widgets/work_mode_selector_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../domain/driver_preferences.dart';
import '../../domain/work_mode.dart';
import '../../providers/driver_operational_provider.dart';

class WorkModeSelectorSheet extends ConsumerStatefulWidget {
  const WorkModeSelectorSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WorkModeSelectorSheet(),
    );
  }

  @override
  ConsumerState<WorkModeSelectorSheet> createState() =>
      _WorkModeSelectorSheetState();
}

class _WorkModeSelectorSheetState extends ConsumerState<WorkModeSelectorSheet> {
  late String _selectedModeId;
  late double _maxTotalDist;
  late double _maxStoreDist;
  late double _minProfitPerKm;
  late int _maxTripMinutes;
  late VehicleType _vehicleType;
  late double _autonomyKm;
  late double _reserveKm;
  late bool _avoidHills;
  bool _isCustomizing = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(driverOperationalProvider).preferences;
    _selectedModeId = prefs.activeWorkModeId;
    _maxTotalDist = prefs.maxTotalDistanceKm;
    _maxStoreDist = prefs.maxStoreDistanceKm;
    _minProfitPerKm = prefs.minProfitPerKm;
    _maxTripMinutes = prefs.maxTripMinutes;
    _vehicleType = prefs.vehicleType;
    _autonomyKm = prefs.estimatedAutonomyKm;
    _reserveKm = prefs.minAutonomyReserveKm;
    _avoidHills = prefs.avoidSteepHills;
  }

  void _applyMode(WorkMode mode) {
    setState(() {
      _selectedModeId = mode.id;
      _maxTotalDist = mode.preferences.maxTotalDistanceKm;
      _maxStoreDist = mode.preferences.maxStoreDistanceKm;
      _minProfitPerKm = mode.preferences.minProfitPerKm;
      _maxTripMinutes = mode.preferences.maxTripMinutes;
      _vehicleType = mode.preferences.vehicleType;
      _autonomyKm = mode.preferences.estimatedAutonomyKm;
      _reserveKm = mode.preferences.minAutonomyReserveKm;
      _avoidHills = mode.preferences.avoidSteepHills;
    });
  }

  void _saveAndClose() {
    final currentPrefs = ref.read(driverOperationalProvider).preferences;
    final updated = currentPrefs.copyWith(
      activeWorkModeId: _selectedModeId,
      maxTotalDistanceKm: _maxTotalDist,
      maxStoreDistanceKm: _maxStoreDist,
      minProfitPerKm: _minProfitPerKm,
      maxTripMinutes: _maxTripMinutes,
      vehicleType: _vehicleType,
      estimatedAutonomyKm: _autonomyKm,
      minAutonomyReserveKm: _reserveKm,
      avoidSteepHills: _avoidHills,
    );
    ref.read(driverOperationalProvider.notifier).updatePreferences(updated);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Modo y filtros actualizados: ${_getModeName(_selectedModeId)}'),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getModeName(String id) {
    return switch (id) {
      'nearby' => 'Modo Cercano 🚲',
      'electric' => 'Modo Eléctrico ⚡',
      'normal' => 'Modo Normal 🛵',
      'max_profit' => 'Maximizar Ganancias 💰',
      _ => 'Modo Personalizado ⚙️',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F120C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withAlpha(80),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MODOS DE TRABAJO 🔥',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF2C1B14),
                      ),
                    ),
                    const Text(
                      'Ajusta cómo La Diabla evalúa y autoacepta tus pedidos',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                // Presets Grid
                const Text(
                  'SELECCIONA UN PERFIL PRECONFIGURADO',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFFDC2626)),
                ),
                const SizedBox(height: 10),
                ...WorkMode.defaultModes.map((mode) {
                  final isSelected = _selectedModeId == mode.id;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFDC2626).withAlpha(15)
                          : (isDark ? const Color(0xFF2C1B14) : Colors.grey.shade50),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFDC2626)
                            : (isDark ? AppColors.dividerDark : Colors.grey.shade300),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Text(mode.emoji, style: const TextStyle(fontSize: 26)),
                      title: Text(
                        mode.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFFDC2626) : null,
                        ),
                      ),
                      subtitle: Text(mode.description, style: const TextStyle(fontSize: 11.5)),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFFDC2626))
                          : null,
                      onTap: () => _applyMode(mode),
                    ),
                  );
                }),

                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'AJUSTES DETALLADOS Y SLIDERS',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFFDC2626)),
                    ),
                    TextButton.icon(
                      icon: Icon(_isCustomizing ? Icons.expand_less_rounded : Icons.tune_rounded, size: 16),
                      label: Text(_isCustomizing ? 'Ocultar' : 'Personalizar', style: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() => _isCustomizing = !_isCustomizing),
                    ),
                  ],
                ),

                if (_isCustomizing) ...[
                  const SizedBox(height: 8),

                  // Slider Distancia Total Máxima
                  _buildSliderTile(
                    title: 'Distancia Máxima de Ruta Total',
                    valueDisplay: '${_maxTotalDist.toStringAsFixed(1)} km',
                    value: _maxTotalDist,
                    min: 1.0,
                    max: 15.0,
                    divisions: 28,
                    onChanged: (val) {
                      setState(() {
                        _maxTotalDist = val;
                        _selectedModeId = 'custom';
                      });
                    },
                  ),

                  // Slider Distancia Máxima a Cocina
                  _buildSliderTile(
                    title: 'Distancia Máxima hasta Cocina Central',
                    valueDisplay: '${_maxStoreDist.toStringAsFixed(1)} km',
                    value: _maxStoreDist,
                    min: 0.5,
                    max: 7.0,
                    divisions: 13,
                    onChanged: (val) {
                      setState(() {
                        _maxStoreDist = val;
                        _selectedModeId = 'custom';
                      });
                    },
                  ),

                  // Slider Ganancia Mínima por Km
                  _buildSliderTile(
                    title: 'Ganancia Mínima por Kilómetro',
                    valueDisplay: _minProfitPerKm == 0 ? 'Sin mínimo' : '\$${_minProfitPerKm.toInt()}/km',
                    value: _minProfitPerKm,
                    min: 0,
                    max: 3000,
                    divisions: 6,
                    onChanged: (val) {
                      setState(() {
                        _minProfitPerKm = val;
                        _selectedModeId = 'custom';
                      });
                    },
                  ),

                  // Selector de Tipo de Vehículo
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C1B14) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? AppColors.dividerDark : Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tipo de Vehículo 🛵', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: VehicleType.values.map((v) {
                            final isSel = _vehicleType == v;
                            return ChoiceChip(
                              label: Text(v.displayName),
                              selected: isSel,
                              selectedColor: const Color(0xFFDC2626),
                              labelStyle: TextStyle(
                                color: isSel ? Colors.white : null,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                              onSelected: (_) {
                                setState(() {
                                  _vehicleType = v;
                                  _selectedModeId = 'custom';
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                  // Evitar pendientes
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C1B14) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? AppColors.dividerDark : Colors.grey.shade300),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Evitar pendientes pronunciadas ⛰️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: const Text('Recomendado si trabajas en bicicleta o vehículo de baja potencia', style: TextStyle(fontSize: 11)),
                      value: _avoidHills,
                      activeThumbColor: const Color(0xFFDC2626),
                      onChanged: (val) {
                        setState(() {
                          _avoidHills = val;
                          _selectedModeId = 'custom';
                        });
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('GUARDAR PREFERENCIAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                onPressed: _saveAndClose,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String valueDisplay,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1B14) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.dividerDark : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(
                valueDisplay,
                style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFDC2626), fontSize: 13),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: const Color(0xFFDC2626),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
