// Rename device - shared by Home's identity chip pencil button and
// Settings > This device's pencil button (§3.1, §3.6: "same action as
// Settings > This device").
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

class GlideRenameDialog extends StatefulWidget {
  const GlideRenameDialog({super.key});

  @override
  State<GlideRenameDialog> createState() => _GlideRenameDialogState();
}

class _GlideRenameDialogState extends State<GlideRenameDialog> {
  late final TextEditingController _controller = TextEditingController(text: context.read(settingsProvider).alias);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      unawaited(context.notifier(settingsProvider).setAlias(value));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: GT.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GT.radiusCard)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.glide.renameDialog.title, style: GT.rowTitle),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 64,
              style: GT.body,
              decoration: InputDecoration(
                filled: true,
                fillColor: GT.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(GT.radiusButton), borderSide: BorderSide.none),
                counterText: '',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GlideTextButtonSmall(label: t.general.cancel, onPressed: () => Navigator.of(context).pop()),
                const SizedBox(width: 8),
                GlideTextButtonSmall(label: t.general.save, color: GT.blue, onPressed: _save),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact text button for dialog action rows (the full-width
/// [GlideTextButton] doesn't fit a `Row`).
class GlideTextButtonSmall extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color color;

  const GlideTextButtonSmall({required this.label, required this.onPressed, this.color = GT.textMuted, super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: color),
      child: Text(label, style: GT.buttonSecondary.copyWith(color: color)),
    );
  }
}
