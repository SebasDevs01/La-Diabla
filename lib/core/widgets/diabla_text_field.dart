// lib/core/widgets/diabla_text_field.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:la_diabla/app/theme/app_colors.dart';
import 'package:la_diabla/app/theme/app_typography.dart';

/// Campo de texto premium con floating label, soporte de contraseña con
/// animación scramble tipo Matrix al mostrar/ocultar.
class DiablaTextField extends StatefulWidget {
  const DiablaTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<DiablaTextField> createState() => _DiablaTextFieldState();
}

class _DiablaTextFieldState extends State<DiablaTextField> {
  bool _obscure = true;
  bool _isAnimating = false;
  Timer? _scrambleTimer;
  String? _scrambledValue;
  TextEditingController? _internalController;
  FocusNode? _internalFocusNode;
  bool _hasFocus = false;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController());

  static const String _chars =
      '!@#\$%^&*()_+-=[]{}|;:,.<>?ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscureText;
    _effectiveFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() => _hasFocus = _effectiveFocusNode.hasFocus);
  }

  @override
  void didUpdateWidget(covariant DiablaTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _obscure = widget.obscureText;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      _effectiveFocusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _scrambleTimer?.cancel();
    _internalController?.dispose();
    if (widget.focusNode == null) {
      _internalFocusNode?.removeListener(_onFocusChange);
      _internalFocusNode?.dispose();
    } else {
      widget.focusNode?.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  String _randomChar() {
    final rng = Random();
    return _chars[rng.nextInt(_chars.length)];
  }

  void _toggleObscure() {
    if (_isAnimating) return;
    final originalText = _effectiveController.text;
    if (originalText.isEmpty) {
      setState(() => _obscure = !_obscure);
      return;
    }

    setState(() {
      _isAnimating = true;
      _obscure = !_obscure;
    });

    const totalIterations = 10;
    int iterations = 0;
    const intervalMs = 30;

    _scrambleTimer?.cancel();
    _scrambleTimer = Timer.periodic(
      const Duration(milliseconds: intervalMs),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        iterations++;
        if (iterations >= totalIterations) {
          timer.cancel();
          setState(() {
            _scrambledValue = null;
            _isAnimating = false;
          });
        } else {
          final scrambled = List.generate(
            originalText.length,
            (i) => _randomChar(),
          ).join();
          setState(() => _scrambledValue = scrambled);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redColor = isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);
    final fillColor = isDark ? AppColors.cardDark : Colors.white;
    final labelColor = isDark ? AppColors.textMutedDark : Colors.grey.shade600;
    final focusedLabelColor = redColor;
    final borderColor = isDark ? AppColors.dividerDark : Colors.grey.shade300;

    final displayController = _isAnimating && _scrambledValue != null
        ? (TextEditingController()..text = _scrambledValue!)
        : _effectiveController;

    final suffixIconWidget = widget.obscureText
        ? GestureDetector(
            onTap: _toggleObscure,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                key: ValueKey(_obscure),
                color: _hasFocus ? redColor : labelColor,
                size: 22,
              ),
            ),
          )
        : widget.suffixIcon;

    return TextFormField(
      controller: _isAnimating && _scrambledValue != null ? displayController : _effectiveController,
      obscureText: widget.obscureText && _obscure && !_isAnimating,
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      onChanged: widget.onChanged,
      maxLines: widget.maxLines,
      readOnly: widget.readOnly || _isAnimating,
      onTap: widget.onTap,
      focusNode: _effectiveFocusNode,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      style: TextStyle(
        fontFamily: AppTypography.bodyFamily,
        fontSize: 15,
        color: isDark ? AppColors.textLight : AppColors.textDark,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: widget.label ?? widget.hint,
        labelStyle: TextStyle(
          fontFamily: AppTypography.bodyFamily,
          fontSize: 15,
          color: labelColor,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          fontFamily: AppTypography.bodyFamily,
          fontSize: 13,
          color: focusedLabelColor,
          fontWeight: FontWeight.w700,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        filled: true,
        fillColor: fillColor,
        prefixIcon: widget.prefixIcon,
        suffixIcon: suffixIconWidget != null
            ? Padding(
                padding: const EdgeInsets.only(right: 6),
                child: suffixIconWidget,
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: redColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        errorStyle: const TextStyle(
          fontFamily: AppTypography.bodyFamily,
          fontSize: 12,
        ),
      ),
    );
  }
}
