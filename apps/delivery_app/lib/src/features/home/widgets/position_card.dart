import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

/// A small non-interactive map of where the rider currently is.
///
/// Its job is reassurance, not navigation — proof that location is genuinely
/// being read. All gestures are off and there are no controls: the real
/// interactive map, with the route and the drop-off, belongs to the Active
/// Delivery screen in a later phase.
///
/// The coordinates stay printed underneath. On a fresh install the map tile can
/// be blank for a beat, or indefinitely if the Maps key is missing, and a pair
/// of moving numbers is unambiguous where an empty grey square is not.
class PositionCard extends StatefulWidget {
  const PositionCard({
    required this.isOnline,
    required this.position,
    super.key,
  });

  final bool isOnline;
  final Position? position;

  @override
  State<PositionCard> createState() => _PositionCardState();
}

class _PositionCardState extends State<PositionCard> {
  GoogleMapController? _controller;

  LatLng? get _target {
    final p = widget.position;
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  String _coordinateLabel() {
    final p = widget.position;
    if (p == null) return 'No fix yet';
    return '${p.latitude.toStringAsFixed(5)}, '
        '${p.longitude.toStringAsFixed(5)}';
  }

  @override
  void didUpdateWidget(PositionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _target;
    if (target != null && _controller != null) {
      // Follow the rider rather than re-creating the map on every ping.
      _controller!.moveCamera(CameraUpdate.newLatLng(target));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;

    return ScaleOnCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
            child: SizedBox(
              height: 140,
              width: double.infinity,
              child: target == null
                  ? const _AwaitingFix()
                  : GoogleMap(
                      key: const ValueKey('rider-position-map'),
                      initialCameraPosition: CameraPosition(
                        target: target,
                        zoom: 15.5,
                      ),
                      onMapCreated: (c) => _controller = c,
                      markers: {
                        Marker(
                          markerId: const MarkerId('me'),
                          position: target,
                        ),
                      },
                      // Reassurance only — nothing here is interactive.
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: false,
                      rotateGesturesEnabled: false,
                      scrollGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      zoomGesturesEnabled: false,
                      liteModeEnabled: true,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(
                  widget.isOnline
                      ? Icons.location_on
                      : Icons.location_searching,
                  color: widget.isOnline ? AppColors.gold : AppColors.ash,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isOnline
                            ? 'Sharing your location'
                            : 'Location idle',
                        style: AppTypography.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _coordinateLabel(),
                        key: const ValueKey('rider-coordinates'),
                        style: AppTypography.data.copyWith(
                          color: AppColors.ash,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isOnline) const GoldPulseIndicator(size: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AwaitingFix extends StatelessWidget {
  const _AwaitingFix();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.graphite,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_searching,
              color: AppColors.ash,
              size: 28,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Finding your position',
              style: AppTypography.caption.copyWith(color: AppColors.ash),
            ),
          ],
        ),
      ),
    );
  }
}
