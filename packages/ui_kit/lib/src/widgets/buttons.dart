import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';

/// Gold-filled primary action.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Widget? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final button = FilledButton(
      onPressed: enabled ? onPressed : null,
      child: _ButtonContent(
        label: label,
        loading: loading,
        icon: icon,
        spinnerColor: enabled ? AppColors.ink : AppColors.ash,
      ),
    );
    return _PressScale(
      enabled: enabled,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// Gold-outline secondary action.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Widget? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final borderColor = enabled
        ? AppColors.gold
        : AppColors.ash.withValues(alpha: 0.45);
    final button = OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(side: BorderSide(color: borderColor)),
      child: _ButtonContent(
        label: label,
        loading: loading,
        icon: icon,
        spinnerColor: enabled ? AppColors.gold : AppColors.ash,
      ),
    );
    return _PressScale(
      enabled: enabled,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// Low-emphasis text action.
class TextActionButton extends StatelessWidget {
  const TextActionButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return _PressScale(
      enabled: enabled,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        child: _ButtonContent(
          label: label,
          loading: loading,
          icon: icon,
          spinnerColor: enabled ? AppColors.gold : AppColors.ash,
        ),
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.loading,
    required this.spinnerColor,
    this.icon,
  });

  final String label;
  final bool loading;
  final Color spinnerColor;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          key: const ValueKey('button-loading-indicator'),
          strokeWidth: 2,
          color: spinnerColor,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          IconTheme.merge(data: const IconThemeData(size: 18), child: icon!),
          const SizedBox(width: AppSpacing.sm),
        ],
        Text(label),
      ],
    );
  }
}

class _PressScale extends StatefulWidget {
  const _PressScale({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.enabled && value != _pressed) setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(_PressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && !reducedMotion ? 0.97 : 1,
        duration: reducedMotion ? Duration.zero : AppMotion.button,
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}
