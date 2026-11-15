import 'package:flutter/material.dart';

class ProductivityRatingWidget extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onRatingChanged;

  const ProductivityRatingWidget({
    super.key,
    required this.value,
    required this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Продуктивность', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          children: List.generate(5, (index) {
            return IconButton(
              icon: Icon(
                Icons.star,
                color: value != null && value! >= index + 1
                    ? Colors.amber
                    : Colors.grey[300],
              ),
              onPressed: () => onRatingChanged(value == index + 1 ? null : index + 1),
            );
          }),
        ),
      ],
    );
  }
}