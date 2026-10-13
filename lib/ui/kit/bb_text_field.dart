import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Search/input field. Uses Material's TextField internally (kit-only) for
/// selection handles and IME support, with all Material decoration removed.
/// A field surface with a line outline; a 2 px [BBTokens.brandEdge] ring while focused.
class BBTextField extends StatefulWidget {
  const BBTextField({
    super.key,
    this.controller,
    this.hint,
    this.semanticLabel,
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

  /// What a screen reader calls the field, with or without text in it (a hint is exposed only while the field is
  /// empty and unfocused). When set, the hint is drawn but not exposed, so the name is read once.
  final String? semanticLabel;
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
  State<BBTextField> createState() => _BBTextFieldState();
}

class _BBTextFieldState extends State<BBTextField> {
  FocusNode? _own;
  bool _focused = false;

  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(BBTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _own)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
      _onFocus();
    }
  }

  void _onFocus() {
    if (_focused != _focus.hasFocus) setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final textStyle = bb.text.body.merge(widget.style);
    final hasError = widget.errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          // DecoratedBox, not Container: the ring's width must not shift the text when focus changes.
          child: DecoratedBox(
            decoration: bb.field(focused: _focused, error: hasError),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: BBSpace.m, vertical: BBSpace.m),
              child: Row(
                children: [
                  if (widget.leadingIcon != null) ...[
                    Icon(widget.leadingIcon, size: 20, color: bb.colors.muted),
                    const SizedBox(width: BBSpace.s),
                  ],
                  Expanded(
                    // TextField needs a Material ancestor; supply an invisible one so the
                    // field also works on kit pages that (correctly) have none.
                    child: Material(
                      type: MaterialType.transparency,
                      child: Semantics(
                        label: widget.semanticLabel,
                        child: TextField(
                          controller: widget.controller,
                          onChanged: widget.onChanged,
                          onSubmitted: widget.onSubmitted,
                          keyboardType: widget.keyboardType,
                          textInputAction: widget.textInputAction,
                          autofocus: widget.autofocus,
                          inputFormatters: widget.inputFormatters,
                          focusNode: _focus,
                          textAlign: widget.textAlign,
                          style: textStyle,
                          cursorColor: bb.brandEdge,
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
                            // With a semanticLabel the hint is only drawn: the label already names the field, and a
                            // hint exposed too would be read twice while the field is empty.
                            hintText: widget.semanticLabel == null ? widget.hint : null,
                            hint: widget.semanticLabel != null && widget.hint != null
                                ? ExcludeSemantics(
                                    child: Text(
                                      widget.hint!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: textStyle.copyWith(color: bb.colors.muted),
                                    ),
                                  )
                                : null,
                            hintMaxLines: 2,
                            hintStyle: textStyle.copyWith(color: bb.colors.muted),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: BBSpace.xs, left: BBSpace.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(widget.errorText!, style: bb.text.caption.copyWith(color: bb.colors.dangerInk)),
            ),
          ),
      ],
    );
  }
}
