import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../state/providers.dart';

/// Text field for entering a 4-digit stop ID.
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

  void _submit() {
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

    // Save and navigate
    ref.read(settingsProvider.notifier).setSelectedStop(text);
    context.push('/board/$text');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter Stop ID',
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '0000',
                  hintStyle: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  counterText: '',
                  errorText: _errorText,
                  prefixIcon: Icon(
                    Icons.pin_drop_outlined,
                    color: theme.colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, size: 20),
                    SizedBox(width: 6),
                    Text('GO'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
