import 'package:flutter/material.dart';

class MoodRatingWidget extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onRatingChanged;

  const MoodRatingWidget({
    super.key,
    required this.value,
    required this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    const emojis = ['😞', '😐', '🙂', '😊', '😍'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Настроение', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Row(
          children: List.generate(5, (index) {
            return GestureDetector(
              onTap: () => onRatingChanged(value == index + 1 ? null : index + 1),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: value == index + 1 ? Colors.green[100] : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  emojis[index],
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}