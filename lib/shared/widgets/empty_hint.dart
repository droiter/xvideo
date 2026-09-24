import 'package:flutter/material.dart';

/// 通用空态占位。
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text, this.detail});

  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final grey = Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 56, color: grey.withOpacity(0.7)),
          const SizedBox(height: 14),
          Text(text,
              style: TextStyle(fontSize: 15, color: grey),
              textAlign: TextAlign.center),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!,
                style: TextStyle(fontSize: 12.5, color: grey.withOpacity(0.8)),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
