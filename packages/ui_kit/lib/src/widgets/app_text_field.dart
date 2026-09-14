import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/src/theme/app_typography.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';

/// Standard labeled Paasel input with helper and error states.
class AppTextField extends StatelessWidget {
  const AppTextField({
    this.label = '',
    this.controller,
    this.hintText,
    this.helperText,
    this.errorText,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.prefixIcon,
    this.prefixIconConstraints,
    this.prefix,
    this.prefixText,
    this.inputFormatters,
    this.maxLength,
    this.autofocus = false,
    this.onChanged,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final Widget? prefixIcon;
  final BoxConstraints? prefixIconConstraints;
  final Widget? prefix;
  final String? prefixText;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: AppTypography.label.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          enabled: enabled,
          autofocus: autofocus,
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          onChanged: onChanged,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: hintText,
            helperText: helperText,
            errorText: errorText,
            prefixIcon: prefixIcon,
            prefixIconConstraints: prefixIconConstraints,
            prefix: prefix,
            prefixText: prefixText,
            counterText: '',
          ),
        ),
      ],
    );
  }
}
