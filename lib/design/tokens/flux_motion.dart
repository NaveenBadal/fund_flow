import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Motion tokens.
///
/// Springs drive anything a finger is holding, because a spring keeps the
/// object under the thumb where a duration curve fights it. Everything else
/// uses a duration and one of two curves — [emphasized] for arrivals and
/// [overshoot] where a surface should feel like it has weight.
///
/// Reduced-motion is not decoration to be skipped: [duration] collapses to
/// zero when the platform asks, so animated widgets keep working as
/// crossfades without a second code path.
abstract final class FluxMotion {
  /// Press, toggle, chip selection.
  static const snap = SpringDescription(mass: 1, stiffness: 520, damping: 32);

  /// Navigation, reveals, most things.
  static const standard = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 28,
  );

  /// Sheets and approval cards — a small overshoot reads as substance.
  static const expressive = SpringDescription(
    mass: 1,
    stiffness: 300,
    damping: 22,
  );

  static const micro = Duration(milliseconds: 120);
  static const quick = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 240);
  static const large = Duration(milliseconds: 400);

  /// Decelerating arrival. The default for anything entering the screen.
  static const emphasized = Cubic(0.2, 0, 0, 1);
  static const exit = Cubic(0.4, 0, 1, 1);
  static const overshoot = Cubic(0.34, 1.28, 0.4, 1);

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// The duration to actually use, honouring the accessibility setting.
  static Duration duration(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;

  /// A simulation for gesture-released motion between two values.
  static SpringSimulation spring(
    SpringDescription description, {
    double from = 0,
    double to = 1,
    double velocity = 0,
  }) => SpringSimulation(description, from, to, velocity);
}

/// Shared-axis page transition: the outgoing page slides and fades out, the
/// incoming one arrives from the other side.
///
/// Used for pushes within a section. A ledger row into its detail page uses
/// the container transform instead, because there the row *becomes* the page
/// and a slide would lose that connection.
class FluxPageRoute<T> extends PageRouteBuilder<T> {
  FluxPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondary) => builder(context),
        transitionsBuilder: (context, animation, secondary, child) {
          if (FluxMotion.reduced(context)) {
            return FadeTransition(opacity: animation, child: child);
          }
          final entering = CurvedAnimation(
            parent: animation,
            curve: FluxMotion.emphasized,
            reverseCurve: FluxMotion.exit,
          );
          final leaving = CurvedAnimation(
            parent: secondary,
            curve: FluxMotion.emphasized,
          );
          return SlideTransition(
            position: Tween(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(entering),
            child: FadeTransition(
              opacity: entering,
              child: SlideTransition(
                position: Tween(
                  begin: Offset.zero,
                  end: const Offset(-0.04, 0),
                ).animate(leaving),
                child: child,
              ),
            ),
          );
        },
      );
}

/// Pushes [builder] with the Flux shared-axis transition.
Future<T?> fluxPush<T>(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(context).push<T>(FluxPageRoute<T>(builder: builder));
