// lib/features/addresses/presentation/screens/addresses_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/diabla_button.dart';
import '../../../../core/widgets/diabla_card.dart';
import '../../../../core/widgets/navigation_app_picker.dart';
import '../../../../domain/entities/address_entity.dart';
import '../../providers/addresses_provider.dart';
import 'map_picker_screen.dart';

class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(addressesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('MIS DIRECCIONES 📍')),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : state.addresses.isEmpty
              ? _buildEmpty(context)
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                  children: [
                    ...state.addresses.map((addr) => _AddressCard(address: addr)),
                    const SizedBox(height: AppSpacing.lg),
                    DiablaButton(
                      text: 'Agregar Nueva Dirección',
                      icon: Icons.add_location_alt_rounded,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MapPickerScreen()),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_off_outlined, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          const Text(
            'Aún no tienes direcciones guardadas',
            style: TextStyle(fontSize: 16, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          DiablaButton(
            text: 'Agregar mi primera dirección',
            icon: Icons.add_location_alt_rounded,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MapPickerScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.address});

  final AddressEntity address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(addressesProvider.notifier);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DiablaCard(
        child: Row(
          children: [
            Icon(
              address.isDefault ? Icons.location_on : Icons.location_on_outlined,
              color: address.isDefault ? AppColors.primary : AppColors.textMuted,
              size: 28,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${_labelEmoji(address.label)} ${address.label.displayName}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (address.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withAlpha(50),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Principal',
                            style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(address.formattedAddress, style: const TextStyle(fontSize: 13)),
                  if (address.reference != null)
                    Text(address.reference!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'default') {
                  notifier.setDefault(address.id);
                } else if (val == 'navigate') {
                  NavigationAppPicker.show(
                    context,
                    latitude: address.latitude,
                    longitude: address.longitude,
                    destinationName: '${_labelEmoji(address.label)} ${address.label.displayName}',
                    addressText: address.formattedAddress,
                  );
                } else if (val == 'delete') {
                  notifier.deleteAddress(address.id);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'default',
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 18, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Establecer como principal'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'navigate',
                  child: Row(
                    children: [
                      Icon(Icons.navigation_outlined, size: 18, color: Color(0xFF00A3DA)),
                      SizedBox(width: 8),
                      Text('Ver en Maps / Waze 🗺️'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Eliminar', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _labelEmoji(AddressLabel label) {
    return switch (label) {
      AddressLabel.home => '🏠',
      AddressLabel.work => '💼',
      AddressLabel.other => '📍',
    };
  }
}


