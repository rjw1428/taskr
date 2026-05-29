import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';

class DividerItem extends StatelessWidget {
  final Task divider;
  final int index;
  final Function(Task) onDelete;

  const DividerItem({
    super.key,
    required this.divider,
    required this.index,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasLabel = divider.title.isNotEmpty;
    return SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Expanded(child: Divider(color: Colors.white38, thickness: 1)),
            if (hasLabel)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  divider.title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (hasLabel) const Expanded(child: Divider(color: Colors.white38, thickness: 1)),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onDelete(divider),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Icon(FontAwesomeIcons.xmark, size: 14, color: Colors.white38),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(left: 4, right: 4),
                child: Icon(FontAwesomeIcons.gripLines, size: 16, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
