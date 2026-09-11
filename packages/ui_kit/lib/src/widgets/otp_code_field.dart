import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/app_typography.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';

/// Six-digit code entry.
///
/// Each app had its own copy of this, and each copy was missing something
/// different: no paste handling, no way to correct a digit in the middle, boxes
/// left full after a rejected code so the only way to retry was backspacing six
/// times. This is the one implementation, and the fiddly parts are the point.
///
/// Behaviour worth knowing about:
///
/// * Typing advances; backspace on an empty box steps back and clears the one
///   before it, which is what people expect and what the hand-rolled versions
///   got wrong.
/// * Pasting or an SMS autofill dropping all six digits into one box spreads
///   them across all six rather than keeping the first and discarding the rest.
/// * [onCompleted] fires once per completed code, not on every rebuild, so an
///   auto-submit cannot fire twice for one entry.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    required this.onCompleted,
    this.length = 6,
    this.enabled = true,
    this.errorText,
    this.autofocus = true,
    this.onChanged,
    super.key,
  });

  /// Called with the full code the moment the last box is filled.
  final ValueChanged<String> onCompleted;

  final int length;

  /// False while a code is being checked, so the digits cannot shift underneath
  /// the request that is verifying them.
  final bool enabled;

  /// Shown beneath the boxes, and tints their borders.
  final String? errorText;

  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  State<OtpCodeField> createState() => OtpCodeFieldState();
}

class OtpCodeFieldState extends State<OtpCodeField> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;

  /// Separate nodes for the key listeners. Built here rather than in `build`
  /// because a FocusNode created during a rebuild is never disposed.
  late final List<FocusNode> _keyNodes;

  /// Guards [OtpCodeField.onCompleted] against firing twice for one code.
  bool _reported = false;

  String get code => _controllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.length,
      (_) => TextEditingController(),
      growable: false,
    );
    _nodes = List.generate(widget.length, (_) => FocusNode(), growable: false);
    _keyNodes = List.generate(
      widget.length,
      (_) => FocusNode(skipTraversal: true, canRequestFocus: false),
      growable: false,
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _nodes) {
      node.dispose();
    }
    for (final node in _keyNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Empties every box and returns focus to the first.
  ///
  /// For a rejected code specifically. A failed *request* must not call this —
  /// wiping six correctly typed digits because the network blipped is a way to
  /// lose a user.
  void clear() {
    for (final controller in _controllers) {
      controller.clear();
    }
    _reported = false;
    if (mounted) {
      setState(() {});
      _nodes.first.requestFocus();
    }
  }

  void _handleChange(int index, String value) {
    // Several digits at once. A real paste or SMS autofill carries the whole
    // code, so spread it; two characters is far more likely to be someone
    // retyping over a box that already had a digit in it, and overwriting the
    // rest of their code would be a nasty surprise.
    if (value.length >= 2) {
      if (value.length >= widget.length) {
        _distribute(value, from: index);
        return;
      }
      _controllers[index].text = value.substring(value.length - 1);
    }

    if (_controllers[index].text.isNotEmpty && index < widget.length - 1) {
      _nodes[index + 1].requestFocus();
    }

    _afterEdit();
  }

  void _distribute(String raw, {required int from}) {
    final digits = raw.replaceAll(RegExp('[^0-9]'), '');
    for (var i = 0; i < widget.length; i++) {
      final source = from + i;
      _controllers[i].text = i < from
          ? _controllers[i].text
          : (source - from < digits.length ? digits[source - from] : '');
    }
    // Land on the first empty box, or the last one if the code is complete.
    final firstEmpty = _controllers.indexWhere((c) => c.text.isEmpty);
    _nodes[firstEmpty == -1 ? widget.length - 1 : firstEmpty].requestFocus();
    _afterEdit();
  }

  /// Backspace on an already-empty box steps back and clears the previous
  /// digit. Without this, correcting a typo means the box you land on still has
  /// the wrong digit in it and a second backspace does nothing visible.
  void _handleKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey != LogicalKeyboardKey.backspace) return;
    if (_controllers[index].text.isNotEmpty || index == 0) return;

    _controllers[index - 1].clear();
    _nodes[index - 1].requestFocus();
    _afterEdit();
  }

  void _afterEdit() {
    setState(() {});
    final current = code;
    widget.onChanged?.call(current);

    if (current.length == widget.length) {
      if (_reported) return;
      _reported = true;
      widget.onCompleted(current);
    } else {
      // Incomplete again, so a later completion is a new one.
      _reported = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < widget.length; i++)
              _Box(
                index: i,
                controller: _controllers[i],
                node: _nodes[i],
                keyNode: _keyNodes[i],
                enabled: widget.enabled,
                hasError: hasError,
                autofocus: widget.autofocus && i == 0,
                onChanged: (value) => _handleChange(i, value),
                onKey: (event) => _handleKey(i, event),
              ),
          ],
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.errorText!,
            key: const ValueKey('otp-error'),
            style: AppTypography.caption.copyWith(color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.index,
    required this.controller,
    required this.node,
    required this.keyNode,
    required this.enabled,
    required this.hasError,
    required this.autofocus,
    required this.onChanged,
    required this.onKey,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode node;
  final FocusNode keyNode;
  final bool enabled;
  final bool hasError;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final ValueChanged<KeyEvent> onKey;

  @override
  Widget build(BuildContext context) {
    final filled = controller.text.isNotEmpty;
    final borderColour = hasError
        ? AppColors.danger
        : (filled ? AppColors.gold : AppColors.ash.withValues(alpha: 0.4));

    return KeyboardListener(
      focusNode: keyNode,
      onKeyEvent: onKey,
      child: AnimatedContainer(
        duration: AppMotion.button,
        width: 46,
        height: 56,
        decoration: BoxDecoration(
          color: filled
              ? AppColors.gold.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(color: borderColour, width: filled ? 1.5 : 1),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        alignment: Alignment.center,
        child: TextField(
          key: ValueKey('otp-box-$index'),
          controller: controller,
          focusNode: node,
          enabled: enabled,
          autofocus: autofocus,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          // One visible digit, but a paste of the whole code still arrives
          // intact — maxLength would silently truncate it to the first digit.
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppTypography.otp,
          cursorColor: AppColors.gold,
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
