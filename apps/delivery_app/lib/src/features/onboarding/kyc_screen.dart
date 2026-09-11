import 'package:core/core.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:delivery_app/src/services/document_uploader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// KYC: vehicle type, ID proof, licence details, payout account.
///
/// The ID upload deliberately uses a plain image picker rather than
/// camera_kit's guided frame. A guided frame exists so two photos of the same
/// parcel can be compared position-for-position; a document photo has nothing
/// to be compared against, so the overlay would be ceremony.
class RiderKycScreen extends ConsumerStatefulWidget {
  const RiderKycScreen({super.key});

  @override
  ConsumerState<RiderKycScreen> createState() => _RiderKycScreenState();
}

class _RiderKycScreenState extends ConsumerState<RiderKycScreen> {
  final _vehicleNumberController = TextEditingController();
  final _accountController = TextEditingController();
  final _ifscController = TextEditingController();
  final _upiController = TextEditingController();

  VehicleChoice _vehicle = VehicleChoice.bike;

  /// Storage URLs, set once a document is actually uploaded. Null means not
  /// yet provided — the submit button reads these, not a separate flag, so the
  /// UI cannot claim a document exists when nothing was stored.
  String? _idProofUrl;
  String? _licenceUrl;
  DocumentKind? _uploading;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _vehicleNumberController.dispose();
    _accountController.dispose();
    _ifscController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  bool get _hasPayoutDetails =>
      _upiController.text.trim().isNotEmpty ||
      (_accountController.text.trim().isNotEmpty &&
          _ifscController.text.trim().isNotEmpty);

  bool get _canSubmit {
    if (_idProofUrl == null || !_hasPayoutDetails) return false;
    if (_uploading != null) return false;
    if (!_vehicle.requiresRegistration) return true;
    return _licenceUrl != null &&
        _vehicleNumberController.text.trim().isNotEmpty;
  }

  void _selectVehicle(VehicleChoice choice) {
    setState(() {
      _vehicle = choice;
      // Switching to a bicycle drops the motor-vehicle details entirely rather
      // than keeping them hidden but populated — the request must not carry a
      // plate number for a bicycle.
      if (!choice.requiresRegistration) {
        _vehicleNumberController.clear();
        _licenceUrl = null;
      }
    });
  }

  Future<void> _pick(DocumentKind kind) async {
    if (_uploading != null) return;
    setState(() {
      _uploading = kind;
      _error = null;
    });

    try {
      final url = await ref
          .read(documentUploaderProvider)
          .pickAndUpload(kind: kind);
      if (!mounted) return;
      setState(() {
        if (url != null) {
          switch (kind) {
            case DocumentKind.idProof:
              _idProofUrl = url;
            case DocumentKind.drivingLicence:
              _licenceUrl = url;
          }
        }
      });
    } on DocumentUploadFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = ref.read(apiClientProvider);
    final result = await client.post<Map<String, dynamic>>(
      '/api/v1/delivery-partners/kyc',
      data: <String, dynamic>{
        'id_proof_url': _idProofUrl,
        'vehicle_type': _vehicle.wire,
        if (_vehicle.requiresRegistration) ...<String, dynamic>{
          'vehicle_number': _vehicleNumberController.text.trim().toUpperCase(),
          'driving_license_url': _licenceUrl,
        },
        'bank_account_details': <String, dynamic>{
          if (_accountController.text.trim().isNotEmpty)
            'account_number': _accountController.text.trim(),
          if (_ifscController.text.trim().isNotEmpty)
            'ifsc': _ifscController.text.trim().toUpperCase(),
          if (_upiController.text.trim().isNotEmpty)
            'upi_id': _upiController.text.trim(),
        },
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );

    if (!mounted) return;
    result.when(
      success: (Map<String, dynamic> _) {
        ref.invalidate(riderDataProvider);
        context.go('/under-review');
      },
      failure: (AppError e) => setState(() {
        _loading = false;
        _error = e.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ListView(
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Get verified',
                style: AppTypography.headline.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'We check every partner before the first delivery.',
                style: AppTypography.body.copyWith(color: AppColors.ash),
              ),
              const SizedBox(height: AppSpacing.xxl),

              Text(
                'What do you ride?',
                style: AppTypography.label.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final choice in VehicleChoice.values)
                    _VehicleChip(
                      choice: choice,
                      selected: _vehicle == choice,
                      onTap: () => _selectVehicle(choice),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              _UploadTile(
                key: const ValueKey('upload-id-proof'),
                label: 'Upload ID proof',
                uploadedLabel: 'ID proof added',
                uploaded: _idProofUrl != null,
                busy: _uploading == DocumentKind.idProof,
                onTap: () => _pick(DocumentKind.idProof),
              ),

              // Bicycle riders never see these fields at all.
              if (_vehicle.requiresRegistration) ...[
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Vehicle number',
                  controller: _vehicleNumberController,
                  hintText: 'e.g. KA01AB1234',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.lg),
                _UploadTile(
                  key: const ValueKey('upload-licence'),
                  label: 'Upload driving licence',
                  uploadedLabel: 'Licence added',
                  uploaded: _licenceUrl != null,
                  busy: _uploading == DocumentKind.drivingLicence,
                  onTap: () => _pick(DocumentKind.drivingLicence),
                ),
              ],

              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Where should we pay you?',
                style: AppTypography.label.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'UPI ID',
                controller: _upiController,
                hintText: 'name@bank',
                helperText: 'Or add a bank account below',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Account number',
                controller: _accountController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'IFSC code',
                controller: _ifscController,
                hintText: 'e.g. SBIN0001234',
                onChanged: (_) => setState(() {}),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _error!,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.xxxl),
              PrimaryButton(
                key: const ValueKey('kyc-submit'),
                label: 'Submit for review',
                onPressed: _canSubmit ? _submit : null,
                loading: _loading,
                expand: true,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleChip extends StatelessWidget {
  const _VehicleChip({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final VehicleChoice choice;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (choice) {
    VehicleChoice.bicycle => Icons.pedal_bike,
    VehicleChoice.bike => Icons.two_wheeler,
    VehicleChoice.scooter => Icons.moped,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.status,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.16)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? AppColors.gold
                  : AppColors.ash.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icon,
                size: 18,
                color: selected ? AppColors.gold : AppColors.ash,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                choice.label,
                style: AppTypography.label.copyWith(
                  color: selected ? AppColors.gold : AppColors.paper,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.label,
    required this.uploadedLabel,
    required this.uploaded,
    required this.onTap,
    this.busy = false,
    super.key,
  });

  final String label;
  final String uploadedLabel;
  final bool uploaded;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      onTap: busy ? null : onTap,
      child: Row(
        children: [
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              uploaded ? Icons.check_circle : Icons.upload_file,
              color: uploaded ? AppColors.success : AppColors.gold,
            ),
          const SizedBox(width: AppSpacing.md),
          Text(
            busy ? 'Uploading…' : (uploaded ? uploadedLabel : label),
            style: AppTypography.bodyMedium,
          ),
          if (uploaded && !busy) ...[
            const Spacer(),
            Text(
              'Replace',
              style: AppTypography.caption.copyWith(color: AppColors.gold),
            ),
          ],
        ],
      ),
    );
  }
}
