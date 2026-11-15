// lib/widgets/notes_input_widget.dart
import 'package:flutter/material.dart';

class NotesInputWidget extends StatefulWidget {
  final String? value;
  final Function(String?) onNotesChanged;
  final int maxLines;

  const NotesInputWidget({
    super.key,
    this.value,
    required this.onNotesChanged,
    this.maxLines = 4,
  });

  @override
  State<NotesInputWidget> createState() => _NotesInputWidgetState();
}

class _NotesInputWidgetState extends State<NotesInputWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(NotesInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.note_alt_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Заметки',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: widget.onNotesChanged,
          controller: _controller,
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.start,
          decoration: InputDecoration(
            hintText: 'Опишите как прошел ваш день...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.all(16),
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ],
    );
  }
}
