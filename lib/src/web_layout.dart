import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Shared responsive rules for the browser UI.
///
/// Keep these decisions out of individual screens so the desktop shell and
/// page content switch layout at the same viewport width.
abstract final class RunNowWebLayout {
  static const desktopBreakpoint = 1024.0;
  static const wideBreakpoint = 1440.0;
  static const maxContentWidth = 1440.0;

  static bool isDesktop(BuildContext context) =>
      kIsWeb && MediaQuery.sizeOf(context).width >= desktopBreakpoint;
}
