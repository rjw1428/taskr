import 'package:flutter/material.dart';
import 'package:taskr/shared/design/tokens.dart';

/// Responsive layout primitives.
///
/// The phone layout is the reference design and is never altered: everything
/// here is a no-op below [Breakpoints.medium]. Wider windows (desktop web,
/// tablets in landscape) get a navigation rail, a centered reading-width
/// column, and dialogs in place of bottom sheets.

/// Window width thresholds, following the Material 3 window size classes.
abstract class Breakpoints {
  /// Below this the app renders its phone layout unchanged.
  static const double medium = 840;

  /// At or above this the navigation rail extends to show labels.
  static const double expanded = 1200;
}

/// The three layouts the app knows how to render.
enum LayoutSize {
  /// Phone: bottom navigation, edge-to-edge pages, bottom sheets.
  compact,

  /// Narrow desktop / tablet: icon rail, centered column, dialogs.
  medium,

  /// Wide desktop: extended rail with labels, centered column, dialogs.
  expanded;

  bool get isCompact => this == LayoutSize.compact;
  bool get isWide => this != LayoutSize.compact;

  static LayoutSize fromWidth(double width) {
    if (width >= Breakpoints.expanded) return LayoutSize.expanded;
    if (width >= Breakpoints.medium) return LayoutSize.medium;
    return LayoutSize.compact;
  }
}

/// The layout for the window that hosts [context]. Reads the window width, not
/// the parent's constraints, so a page nested inside a [ContentColumn] still
/// knows it is on a wide screen.
LayoutSize layoutSizeOf(BuildContext context) => LayoutSize.fromWidth(MediaQuery.sizeOf(context).width);

/// Maximum widths for a [ContentColumn].
abstract class ContentWidths {
  /// Lists and forms: a comfortable reading width.
  static const double reading = 840;

  /// Dashboards that lay cards out in two columns.
  static const double dashboard = 1160;

  /// Modal dialogs that stand in for bottom sheets on wide screens.
  static const double dialog = 560;
}

/// Centers [child] in a column of at most [maxWidth] on wide screens, painting
/// the scaffold background around it. On a compact layout it renders [child]
/// unchanged, with the exact constraints it would have had otherwise.
class ContentColumn extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  /// Horizontal breathing room on wide screens only.
  final double gutter;

  const ContentColumn({
    super.key,
    required this.child,
    this.maxWidth = ContentWidths.reading,
    this.gutter = Insets.xl,
  });

  @override
  Widget build(BuildContext context) {
    if (layoutSizeOf(context).isCompact) return child;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth + gutter * 2),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            // Expand so the child sees tight constraints, as it does on a phone.
            child: SizedBox.expand(child: child),
          ),
        ),
      ),
    );
  }
}

/// Presents [builder] the way the current layout expects a transient form to
/// appear: a modal bottom sheet on a phone, a centered dialog on a wide screen.
/// Sheet-only flags are honored on the phone path and ignored by the dialog.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  double maxWidth = ContentWidths.dialog,
}) {
  if (layoutSizeOf(context).isCompact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: Insets.xxl, vertical: Insets.xxl),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.lg)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: Builder(builder: builder)),
      ),
    ),
  );
}
