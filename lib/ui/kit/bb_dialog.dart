import 'package:flutter/widgets.dart';

import 'bb_button.dart';
import 'tokens.dart';

class BBDialogAction<T> {
  const BBDialogAction({required this.label, required this.value, this.primary = false});
  final String label;
  final T value;
  final bool primary;
}

/// Centred card dialog (replaces AlertDialog).
abstract final class BBDialog {
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? message,
    required List<BBDialogAction<T>> actions,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: const Color(0x661C2A3A),
      transitionDuration: BBMotion.of(context, BBMotion.standard),
      pageBuilder: (dialogContext, _, _) => _DialogCard<T>(title: title, message: message, actions: actions),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: BBMotion.curve);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
        );
      },
    );
  }
}

class _DialogCard<T> extends StatelessWidget {
  const _DialogCard({required this.title, required this.message, required this.actions});

  final String title;
  final String? message;
  final List<BBDialogAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    // Keep the card inside the safe area (and above the keyboard) so its
    // height is bounded: long text scrolls, the actions stay on screen.
    final insets = MediaQuery.paddingOf(context) + EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom);
    return Padding(
      padding: insets + const EdgeInsets.all(BBSpace.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Semantics(
            namesRoute: true,
            explicitChildNodes: true,
            label: title,
            child: DecoratedBox(
              decoration: bb.floating(radius: BBRadius.sheet),
              child: Padding(
                padding: const EdgeInsets.all(BBSpace.xl),
                child: DefaultTextStyle(
                  style: bb.text.body,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(header: true, child: Text(title, style: bb.text.headline)),
                              if (message != null) ...[
                                const SizedBox(height: BBSpace.s),
                                Text(message!, style: bb.text.body.copyWith(color: bb.colors.muted)),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: BBSpace.xl),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: BBSpace.s,
                        runSpacing: BBSpace.s,
                        children: [
                          for (final a in actions)
                            BBButton(
                              label: a.label,
                              kind: a.primary ? BBButtonKind.primary : BBButtonKind.quiet,
                              onPressed: () => Navigator.of(context).pop(a.value),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
