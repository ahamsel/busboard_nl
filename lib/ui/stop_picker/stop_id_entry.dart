import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../routing/push_once.dart';
import '../../state/providers.dart';
import '../kit/kit.dart';

class StopIdEntry extends ConsumerStatefulWidget {
  const StopIdEntry({super.key});

  @override
  ConsumerState<StopIdEntry> createState() => _StopIdEntryState();
}

class _StopIdEntryState extends ConsumerState<StopIdEntry> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(PushOnceCallback push) {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      setState(() => _errorText = 'Please enter a stop ID');
      return;
    }

    if (text.length != 4 || int.tryParse(text) == null) {
      setState(() => _errorText = 'Stop ID must be 4 digits');
      return;
    }

    setState(() => _errorText = null);

    // Save and navigate (once for a quick double tap on Go)
    ref.read(settingsProvider.notifier).setSelectedStop(text);
    push('/board/$text');
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return PushOnce(builder: (context, push) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stop number', style: bb.text.label.copyWith(color: bb.colors.muted)),
        const SizedBox(height: BBSpace.s),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BBTextField(
                controller: _controller,
                focusNode: _focusNode,
                hint: 'Stop number on the pole',
                // The same words name the field for screen readers, so it is not announced by its typed value alone.
                semanticLabel: 'Stop number on the pole',
                leadingIcon: BBIcons.pin,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.go,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                errorText: _errorText,
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
                onSubmitted: (_) => _submit(push),
              ),
            ),
            const SizedBox(width: BBSpace.s),
            BBButton(label: 'Go', icon: BBIcons.search, onPressed: () => _submit(push)),
          ],
        ),
      ],
    ));
  }
}
