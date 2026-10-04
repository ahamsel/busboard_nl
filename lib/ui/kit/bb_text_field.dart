import 'package:flutter/material.dart';

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
  });

  final TextEditingController? controller;
  final String? hint;
  final IconData? leadingIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.m),
      decoration: BoxDecoration(
        color: bb.colors.surface,
        borderRadius: BorderRadius.circular(BBRadius.button),
        border: Border.all(color: bb.colors.line),
      ),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 20, color: bb.colors.muted),
            const SizedBox(width: BBSpace.s),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              autofocus: autofocus,
              style: bb.text.body,
              cursorColor: bb.colors.brand,
              decoration: InputDecoration.collapsed(
                hintText: hint,
                hintStyle: bb.text.body.copyWith(color: bb.colors.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
