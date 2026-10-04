import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Search/input field. Uses Material's TextField internally (kit-only) for
/// selection handles and IME support, with all Material decoration removed.
class BBTextField extends StatelessWidget {
  const BBTextField({
    super.key,
    this.controller,
    this.hint,
    this.leadingIcon,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.inputFormatters,
    this.errorText,
    this.focusNode,
    this.textAlign = TextAlign.start,
    this.style,
  });

  final TextEditingController? controller;
  final String? hint;
  final IconData? leadingIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;
  final FocusNode? focusNode;
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final textStyle = bb.text.body.merge(style);
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.m),
          decoration: BoxDecoration(
            color: bb.colors.surface,
            borderRadius: BorderRadius.circular(BBRadius.button),
            border: Border.all(color: hasError ? bb.colors.dangerInk : bb.colors.line, width: hasError ? 1.5 : 1),
          ),
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 20, color: bb.colors.muted),
                const SizedBox(width: BBSpace.s),
              ],
              Expanded(
                // TextField needs a Material ancestor; supply an invisible one so the
                // field also works on kit pages that (correctly) have none.
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    autofocus: autofocus,
                    inputFormatters: inputFormatters,
                    focusNode: focusNode,
                    textAlign: textAlign,
                    style: textStyle,
                    cursorColor: bb.colors.brand,
                    // Fully bare field: BBTextField draws its own container, so the
                    // theme's filled/outlined InputDecorationTheme must not leak in.
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      hintText: hint,
                      hintMaxLines: 2,
                      hintStyle: textStyle.copyWith(color: bb.colors.muted),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: BBSpace.xs, left: BBSpace.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(errorText!, style: bb.text.caption.copyWith(color: bb.colors.dangerInk)),
            ),
          ),
      ],
    );
  }
}
