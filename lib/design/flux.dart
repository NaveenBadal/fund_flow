/// Flux — Fund Flow's design system.
///
/// Deliberately knows nothing about this app: no imports from `lib/features`,
/// `lib/domain` or anything else above it. Money arrives here already formatted
/// and categories arrive already resolved to a colour, which is what keeps the
/// system reviewable on its own and demonstrable in the `/design` gallery
/// without booting the app.
library;

export 'charts/flux_bars.dart';
export 'charts/flux_delta.dart';
export 'charts/flux_donut.dart';
export 'charts/flux_ring.dart';
export 'charts/flux_sparkline.dart';
export 'components/flux_avatar.dart';
export 'components/flux_button.dart';
export 'components/flux_chip.dart';
export 'components/flux_field.dart';
export 'components/flux_list.dart';
export 'components/flux_money.dart';
export 'components/flux_page.dart';
export 'components/flux_pressable.dart';
export 'components/flux_sheet.dart';
export 'components/flux_states.dart';
export 'components/flux_surface.dart';
export 'theme/flux_theme.dart';
