import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Explains why background location is needed, before the OS asks.
///
/// This is not the customer app's one-time "where are you" capture and it
/// should not read like it. The OS "Always allow" dialog, shown cold, sounds
/// like an app asking to follow someone around. Said plainly first — customers
/// and shops are watching a delivery happen live — it reads as the obvious
/// requirement it actually is.
class LocationPermissionCard extends StatelessWidget {
  const LocationPermissionCard({
    required this.access,
    required this.onRequest,
    required this.onOpenSettings,
    super.key,
  });

  final LocationAccess access;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return switch (access) {
      LocationAccess.always => const SizedBox.shrink(),
      LocationAccess.whileInUseOnly => _ForegroundOnlyCard(
        onOpenSettings: onOpenSettings,
      ),
      LocationAccess.denied => _DeniedCard(onOpenSettings: onOpenSettings),
      LocationAccess.unknown => _ExplainerCard(onRequest: onRequest),
    };
  }
}

class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      key: const ValueKey('location-explainer-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location, color: AppColors.gold),
              const SizedBox(width: AppSpacing.md),
              Text('Location access', style: AppTypography.title),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Paasel Rider needs your location even while the app is in the '
            'background. Customers and shops watch your delivery move in real '
            'time, and that stops working the moment your screen locks unless '
            'you allow it always.',
            style: AppTypography.body.copyWith(color: AppColors.ash),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your phone will ask next. Choose "Allow all the time".',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(label: 'Continue', onPressed: onRequest, expand: true),
        ],
      ),
    );
  }
}

class _ForegroundOnlyCard extends StatelessWidget {
  const _ForegroundOnlyCard({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      key: const ValueKey('location-foreground-only-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Only allowed while the app is open',
                  style: AppTypography.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Tracking will stop the second your screen locks, which leaves the '
            'customer looking at a frozen map. Change it to "Allow all the '
            'time" and you can go online.',
            style: AppTypography.body.copyWith(color: AppColors.ash),
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Open settings',
            onPressed: onOpenSettings,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _DeniedCard extends StatelessWidget {
  const _DeniedCard({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      key: const ValueKey('location-denied-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_off, color: AppColors.danger),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('Location is off', style: AppTypography.title),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Deliveries cannot be assigned without it — there is no way to '
            'tell which orders are near you.',
            style: AppTypography.body.copyWith(color: AppColors.ash),
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Open settings',
            onPressed: onOpenSettings,
            expand: true,
          ),
        ],
      ),
    );
  }
}
