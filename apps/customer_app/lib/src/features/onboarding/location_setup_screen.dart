import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:customer_app/src/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Pins a delivery address to a real position.
///
/// The explainer comes before the OS dialog on purpose: a permission prompt
/// arriving unannounced is the single most refused moment in an app like this,
/// and "so we can show shops that deliver to you" is the whole justification.
class LocationSetupScreen extends ConsumerStatefulWidget {
  const LocationSetupScreen({super.key});

  @override
  ConsumerState<LocationSetupScreen> createState() =>
      _LocationSetupScreenState();
}

class _LocationSetupScreenState extends ConsumerState<LocationSetupScreen> {
  final _addressController = TextEditingController();

  bool _busy = false;
  Position? _position;
  LocationDenial? _denial;
  String _selectedLabel = 'Home';

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() {
      _busy = true;
      _denial = null;
    });
    try {
      final service = ref.read(locationServiceProvider);
      final position = await service.current();
      if (!mounted) return;
      setState(() {
        _position = position;
        _busy = false;
      });

      // Best-effort, and after the confirm step is already on screen. Making
      // the user wait on a reverse-geocode round trip to see their own
      // position would trade something certain for something optional.
      if (_addressController.text.trim().isEmpty) {
        final described = await service.describe(position);
        if (!mounted || _position != position) return;
        setState(() {
          _addressController.text = described ?? _coordinateLabel(position);
        });
      }
    } on LocationUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _denial = e.denial;
      });
    }
  }

  Future<void> _save() async {
    final position = _position;
    if (position == null) return;

    setState(() => _busy = true);
    final text = _addressController.text.trim();
    final result = await ref
        .read(addressRepositoryProvider)
        .createAddress(
          label: _selectedLabel,
          // The real fix, not a constant. Delivery distance and the fee are
          // computed from this server-side.
          lat: position.latitude,
          lng: position.longitude,
          addressText: text.isEmpty ? _coordinateLabel(position) : text,
        );

    if (!mounted) return;
    result.when(
      success: (_) {
        ref.invalidate(addressListProvider);
        context.go('/home');
      },
      failure: (AppError e) {
        setState(() => _busy = false);
        AppSnackbar.show(
          context,
          message: e.message,
          variant: AppSnackbarVariant.error,
        );
      },
    );
  }

  static String _coordinateLabel(Position p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: AnimatedSwitcher(
            duration: AppMotion.status,
            child: _position == null ? _explainer() : _confirm(),
          ),
        ),
      ),
    );
  }

  Widget _explainer() {
    final denial = _denial;

    return Column(
      key: const ValueKey('location-explainer'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.huge),
        const Icon(Icons.location_on_outlined, size: 48, color: AppColors.gold),
        const SizedBox(height: AppSpacing.xl),
        Text('Where do you want delivery?', style: AppTypography.headline),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Passel needs your location to show shops that actually deliver to '
          'you, and to work out the delivery fee.',
          style: AppTypography.body.copyWith(color: AppColors.ash),
        ),
        if (denial != null) ...[
          const SizedBox(height: AppSpacing.xl),
          ScaleOnCard(
            key: const ValueKey('location-denied'),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.warning),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(denial.message, style: AppTypography.body),
                ),
              ],
            ),
          ),
        ],
        const Spacer(),
        if (denial != null && denial.needsSettings)
          PrimaryButton(
            key: const ValueKey('open-settings'),
            label: 'Open Settings',
            onPressed: () => ref.read(locationServiceProvider).openSettings(),
            expand: true,
          )
        else
          PrimaryButton(
            key: const ValueKey('allow-location'),
            label: denial == null ? 'Allow Location' : 'Try again',
            onPressed: _busy ? null : _detect,
            loading: _busy,
            expand: true,
          ),
        if (denial == LocationDenial.serviceDisabled) ...[
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: 'Location settings',
            onPressed: () =>
                ref.read(locationServiceProvider).openLocationSettings(),
            expand: true,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _confirm() {
    final position = _position!;

    return Column(
      key: const ValueKey('location-confirm'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.huge),
        Text('Confirm your address', style: AppTypography.headline),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Add your flat or building so the rider can find you.',
          style: AppTypography.body.copyWith(color: AppColors.ash),
        ),
        const SizedBox(height: AppSpacing.xl),
        ScaleOnCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.my_location,
                    size: 16,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _coordinateLabel(position),
                    key: const ValueKey('detected-coordinates'),
                    style: AppTypography.data,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Address',
                controller: _addressController,
                hintText: 'Flat 3B, Rose Apartments',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                children: ['Home', 'Work', 'Other'].map((label) {
                  return ChoiceChip(
                    label: Text(label),
                    selected: _selectedLabel == label,
                    onSelected: (_) => setState(() => _selectedLabel = label),
                    selectedColor: AppColors.gold.withValues(alpha: 0.2),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const Spacer(),
        PrimaryButton(
          key: const ValueKey('save-address'),
          label: 'Save and continue',
          onPressed: _busy ? null : _save,
          loading: _busy,
          expand: true,
        ),
        const SizedBox(height: AppSpacing.md),
        TextActionButton(
          label: 'Use a different location',
          onPressed: _busy ? null : () => setState(() => _position = null),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
