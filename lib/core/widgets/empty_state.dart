import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

/// What a place is for while it has nothing in it: an icon in a soft lamp,
/// one line that names the state, one that says how it fills up, and the
/// action that does it. [compact] is for a section inside a page (recent
/// fills) rather than a whole page.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.secondaryAction,
    this.compact = false,
  });

  final SottoIcons icon;
  final String title;
  final String body;
  final Widget? action;
  final Widget? secondaryAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lamp = compact ? 36.0 : 48.0;
    final content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 420 : 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: lamp,
            height: lamp,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  p.primary.withValues(alpha: p.isDark ? 0.20 : 0.12),
                  p.primary.withValues(alpha: 0.04),
                ],
              ),
              border: Border.all(color: p.primary.withValues(alpha: p.isDark ? 0.28 : 0.20)),
            ),
            child: SottoIcon(icon, size: compact ? 16 : 20, color: p.primaryText),
          ),
          SizedBox(height: compact ? Space.s3 : Space.s4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: (compact ? TypeScale.bodyStrong : TypeScale.title3).copyWith(color: p.inkPrimary),
          ),
          const SizedBox(height: Space.s1_5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: (compact ? TypeScale.caption : TypeScale.body).copyWith(color: p.inkSecondary),
          ),
          if (action != null || secondaryAction != null) ...[
            SizedBox(height: compact ? Space.s3 : Space.s5),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: [?action, ?secondaryAction],
            ),
          ],
        ],
      ),
    );
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? Space.s6 : Space.s10, horizontal: Space.s4),
        child: content,
      ),
    );
  }
}
