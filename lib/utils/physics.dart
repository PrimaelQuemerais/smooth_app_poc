import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

class VerticalClampScroll extends StatefulWidget {
  const VerticalClampScroll({
    required this.steps,
    required this.child,
    super.key,
  }) : assert(steps.length >= 2);

  final List<double> steps;
  final Widget child;

  @override
  State<VerticalClampScroll> createState() => _VerticalClampScrollState();
}

class _VerticalClampScrollState extends State<VerticalClampScroll> {
  late final Iterable<double> _reversedSteps;
  final VerticalClampScrollLimiter _limiter = VerticalClampScrollLimiter();
  ScrollDirection? _direction;
  ScrollMetrics? _startMetrics;

  @override
  void initState() {
    super.initState();
    _reversedSteps = widget.steps.reversed;
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: _CustomScrollBehavior(
        VerticalSnapScrollPhysics(
          steps: widget.steps,
        ),
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notif) {
          if (notif.metrics.axisDirection == AxisDirection.left ||
              notif.metrics.axisDirection == AxisDirection.right) {
            return false;
          }

          if (notif is UserScrollNotification) {
            _direction = notif.direction;

            if (notif.direction != ScrollDirection.idle) {
              _startMetrics = notif.metrics;
            }
          } else if (notif is ScrollUpdateNotification) {
            _onScrollUpdate(notif);
          } else if (notif is ScrollEndNotification) {
            _onScrollEnd(notif);
          }

          return true;
        },
        child: ChangeNotifierProvider(
          create: (_) => _limiter,
          child: widget.child,
        ),
      ),
    );
  }

  void _onScrollEnd(ScrollEndNotification notif) {
    if (notif.dragDetails != null) {
      var (double? min, double? max) = _getRange(
        widget.steps,
        notif.metrics.pixels,
      );

      double? scrollTo;
      // Down
      if (_direction == ScrollDirection.reverse && max != null) {
        scrollTo = max;
      } else if (_direction == ScrollDirection.forward && min != null) {
        scrollTo = min;
      }

      if (scrollTo != null) {
        Future.delayed(Duration.zero, () {
          if (mounted) {
            context.read<ScrollController>().animateTo(
                  scrollTo!,
                  curve: Curves.easeOutCubic,
                  duration: const Duration(milliseconds: 500),
                );
          }
        });
      }
    }
  }

  void _onScrollUpdate(ScrollUpdateNotification notif) {
    if (_direction != ScrollDirection.forward || _startMetrics == null) {
      return;
    }

    if (_limiter.value != null && notif.metrics.pixels > _limiter.value!) {
      context.read<ScrollController>().position.correctPixels(_limiter.value!);
      return;
    }

    for (int i = 0; i != _reversedSteps.length; i++) {
      if (_blockScrollIfNecessary(
          notif, _reversedSteps.elementAt(i), i == _reversedSteps.length - 1)) {
        break;
      }
    }
  }

  bool _blockScrollIfNecessary(
    ScrollUpdateNotification notif,
    double step,
    bool isLast,
  ) {
    if (isLast) {
      if (_startMetrics!.extentBefore >= step) {
        if (notif.metrics.pixels <= step) {
          context.read<ScrollController>().position.correctPixels(step);
        }
        return true;
      }
    }

    return false;
  }
}

class VerticalClampScrollLimiter extends ValueNotifier<double?> {
  VerticalClampScrollLimiter() : super(null);

  void limitScroll(double height) {
    value = height;
  }
}

/// A custom [ScrollPhysics] that snaps to specific [steps].
/// ignore: must_be_immutable
class VerticalSnapScrollPhysics extends ClampingScrollPhysics {
  VerticalSnapScrollPhysics({
    required List<double> steps,
    this.lastStepBlocking = true,
    final ScrollPhysics? parent,
  })  : steps = steps.toList()..sort(),
        ignoreNextScroll = false,
        super(parent: parent ?? const BouncingScrollPhysics());

  final List<double> steps;

  // If true, scrolling from the bottom with be blocked at the last step
  // If false, scrolling from the bottom will continue
  final bool lastStepBlocking;
  bool ignoreNextScroll;

  @override
  ClampingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return VerticalSnapScrollPhysics(
      parent: buildParent(ancestor),
      steps: steps,
      lastStepBlocking: lastStepBlocking,
    );
  }

  double? _lastPixels;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final Tolerance tolerance = toleranceFor(position);
    if (velocity.abs() < tolerance.velocity) {
      return null;
    }
    if (velocity > 0.0 && position.pixels >= position.maxScrollExtent) {
      ignoreNextScroll = false;
      return null;
    }
    if (velocity < 0.0 && position.pixels <= position.minScrollExtent) {
      ignoreNextScroll = false;
      return null;
    }

    final Simulation? simulation =
        super.createBallisticSimulation(position, velocity);
    final double? simulationX = simulation?.x(double.infinity);
    double? proposedPixels = simulationX;

    if (simulation == null || proposedPixels == null) {
      final (double? min, _) = _getRange(steps, position.pixels);

      if (min != null && min != steps.last && ignoreNextScroll) {
        return ScrollSpringSimulation(
          spring,
          position.pixels,
          min,
          velocity,
          tolerance: toleranceFor(position),
        );
      } else {
        ignoreNextScroll = false;
        return null;
      }
    }

    ignoreNextScroll = false;
    final (double? min, double? max) = _getRange(steps, position.pixels);
    bool hasChanged = false;
    if (min != null && max == null) {
      if (proposedPixels < min) {
        proposedPixels = min;
        hasChanged = true;
      }
    } else if (min != null && max != null) {
      if (position.pixels - proposedPixels > 0) {
        proposedPixels = min;
      } else {
        proposedPixels = max;
      }
      hasChanged = true;
    }

    if (_lastPixels == null) {
      _lastPixels = proposedPixels;
    } else {
      _lastPixels = _fixInconsistency(proposedPixels);
    }

    /// Smooth scroll to a step
    if (hasChanged && (lastStepBlocking || position.pixels < steps.last)) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        _lastPixels!,
        velocity,
        tolerance: tolerance,
      );
    }

    /// Normal scrolling
    return super.createBallisticSimulation(position, velocity);
  }

  // In some cases, the proposed pixels have a giant space and finding the range
  // is incorrect. In that case, we ensure to have a contiguous range.
  double _fixInconsistency(double proposedPixels) {
    return fixInconsistency(steps, proposedPixels, _lastPixels!);
  }

  static double fixInconsistency(
    List<double> steps,
    double proposedPixels,
    double initialPixelPosition,
  ) {
    final int newPosition = _getStepPosition(steps, proposedPixels);
    final int oldPosition = _getStepPosition(steps, initialPixelPosition);

    if (newPosition - oldPosition >= 2) {
      return steps[math.min(newPosition - 1, 0)];
    } else if (newPosition - oldPosition <= -2) {
      return steps[math.min(newPosition + 1, steps.length - 1)];
    }

    return proposedPixels;
  }

  static int _getStepPosition(List<double> steps, double pixels) {
    for (int i = steps.length - 1; i >= 0; i--) {
      final double step = steps.elementAt(i);

      if (pixels >= step) {
        return i;
      }
    }

    return 0;
  }
}

(double?, double?) _getRange(List<double> steps, double position) {
  for (int i = steps.length - 1; i >= 0; i--) {
    final double step = steps[i];

    if (i == steps.length - 1 && position > step) {
      return (step, null);
    } else if (position > step && position < steps[i + 1]) {
      return (step, steps[i + 1]);
    }
  }

  return (null, null);
}

class _CustomScrollBehavior extends ScrollBehavior {
  const _CustomScrollBehavior(this.physics);

  final ScrollPhysics physics;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => physics;
}

class HorizontalSnapScrollPhysics extends ScrollPhysics {
  const HorizontalSnapScrollPhysics({super.parent, required this.snapSize});

  final double snapSize;

  @override
  HorizontalSnapScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return HorizontalSnapScrollPhysics(
        parent: buildParent(ancestor), snapSize: snapSize);
  }

  double _getPage(ScrollMetrics position) {
    return position.pixels / snapSize;
  }

  double _getPixels(ScrollMetrics position, double page) {
    return page * snapSize;
  }

  double _getTargetPixels(
      ScrollMetrics position, Tolerance tolerance, double velocity) {
    double page = _getPage(position);
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    return _getPixels(position, page.roundToDouble());
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // If we're out of range and not headed back in range, defer to the parent
    // ballistics, which should put us back in range at a page boundary.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final Tolerance tolerance = toleranceFor(position);
    final double target = _getTargetPixels(position, tolerance, velocity);
    if (target != position.pixels) {
      return ScrollSpringSimulation(spring, position.pixels, target, velocity,
          tolerance: tolerance);
    }
    return null;
  }

  @override
  bool get allowImplicitScrolling => false;
}
