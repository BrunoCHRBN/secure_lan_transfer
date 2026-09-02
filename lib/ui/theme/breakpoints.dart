import 'package:flutter/material.dart';

/// Screen layout breakpoints for responsive UI.
enum LayoutBreakpoint {
  compact, // Mobile < 600px
  medium,  // Tablet 600px - 1023px
  expanded; // Desktop / Wide >= 1024px

  static LayoutBreakpoint fromWidth(double width) {
    if (width < 600) {
      return LayoutBreakpoint.compact;
    } else if (width < 1024) {
      return LayoutBreakpoint.medium;
    } else {
      return LayoutBreakpoint.expanded;
    }
  }

  bool get isCompact => this == LayoutBreakpoint.compact;
  bool get isMedium => this == LayoutBreakpoint.medium;
  bool get isExpanded => this == LayoutBreakpoint.expanded;
}

/// BuildContext extension helpers for responsive queries.
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  LayoutBreakpoint get breakpoint => LayoutBreakpoint.fromWidth(screenWidth);

  bool get isCompact => breakpoint.isCompact;
  bool get isMedium => breakpoint.isMedium;
  bool get isExpanded => breakpoint.isExpanded;
}
