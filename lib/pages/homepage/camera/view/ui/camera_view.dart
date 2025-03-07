import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smoothapp_poc/navigation.dart';
import 'package:smoothapp_poc/pages/homepage/camera/view/camera_state_manager.dart';
import 'package:smoothapp_poc/pages/homepage/camera/view/ui/camera_buttons_bar.dart';
import 'package:smoothapp_poc/pages/homepage/camera/view/ui/camera_message.dart';
import 'package:smoothapp_poc/pages/homepage/camera/view/ui/camera_overlay.dart';
import 'package:smoothapp_poc/pages/homepage/homepage.dart';
import 'package:smoothapp_poc/pages/product/header/product_compatibility_header.dart';
import 'package:smoothapp_poc/pages/product/header/product_tabs.dart';
import 'package:smoothapp_poc/pages/product/product_page.dart';
import 'package:smoothapp_poc/resources/app_animations.dart';
import 'package:smoothapp_poc/utils/num_utils.dart';
import 'package:smoothapp_poc/utils/provider_utils.dart';
import 'package:smoothapp_poc/utils/system_ui.dart';
import 'package:smoothapp_poc/utils/widgets/modal_sheet.dart';
import 'package:smoothapp_poc/utils/widgets/offline_size_widget.dart';
import 'package:smoothapp_poc/utils/widgets/useful_widgets.dart';
import 'package:torch_light/torch_light.dart';

class CameraView extends StatefulWidget {
  const CameraView({
    required this.controller,
    required this.progress,
    required this.onClosed,
    super.key,
  });

  final CustomScannerController controller;
  final double progress;
  final VoidCallback onClosed;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  /// A [Stream] for the [CameraOverlay]
  final StreamController<DetectedBarcode> _barcodeStream = StreamController();

  /// To notify the user that the barcode is already the current one, we wait
  /// for 2 seconds, before vibrating
  DateTime? _lastDetectionOfTheSameBarcode;

  @override
  Widget build(BuildContext context) {
    final bool isCameraFullyVisible = _isCameraFullyVisible();

    return Provider.value(
      value: widget.controller,
      child: ValueListener<CameraViewStateManager, CameraViewState>(
        onValueChanged: (CameraViewState state) {
          if (state is CameraViewProductAvailableState) {
            showProduct(context, state.product);
          }
        },
        child: Builder(builder: (BuildContext context) {
          return Consumer<SheetVisibilityNotifier>(
            builder: (
              BuildContext context,
              SheetVisibilityNotifier notifier,
              Widget? child,
            ) {
              return Offstage(
                offstage: notifier.isFullyVisible,
                child: child!,
              );
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: MobileScanner(
                    overlayBuilder: (_, __) => CameraOverlay(
                      barcodes: _barcodeStream.stream,
                    ),
                    controller: widget.controller._controller,
                    placeholderBuilder: (_, __) => const SizedBox.expand(
                        child: ColoredBox(color: Colors.black)),
                    onDetect: (BarcodeCapture capture) {
                      // Only pass if the camera is fully visible and the sheet is not visible and/or scrolled
                      if (HomePage.of(context).isCameraFullyVisible &&
                          context
                                  .read<
                                      DraggableScrollableLockAtTopController?>()
                                  ?.isScrolled !=
                              true) {
                        final String barcode = capture.barcodes.first.rawValue!;
                        _barcodeStream.add(
                          DetectedBarcode(
                            barcode: barcode,
                            corners: capture.barcodes.first.corners,
                            width: capture.size.width,
                            height: capture.size.height,
                          ),
                        );

                        final CameraViewStateManager stateManager =
                            CameraViewStateManager.of(context);

                        if (stateManager.currentBarcode != barcode) {
                          _lastDetectionOfTheSameBarcode = DateTime.now();
                          stateManager.onBarcodeDetected(barcode);
                        } else {
                          _vibrateWithTheSameBarcode();
                        }
                      }
                    },
                  ),
                ),
                Positioned(
                  top: 0.0,
                  left: 0.0,
                  right: 0.0,
                  child: Offstage(
                    offstage: !isCameraFullyVisible,
                    child: CameraButtonBars(
                      onClosed: widget.onClosed,
                    ),
                  ),
                ),
                if (isCameraFullyVisible &&
                    SheetVisibilityNotifier.of(context).isGone)
                  Positioned(
                    bottom: 20.0,
                    left: 0.0,
                    right: 0.0,
                    child: SafeArea(
                      bottom: true,
                      child: _MessageOverlay(),
                    ),
                  ),
                Positioned.fill(
                  child: _OpaqueOverlay(
                    isCameraFullyVisible: isCameraFullyVisible,
                    progress: widget.progress,
                  ),
                ),
                Positioned(
                  top: 200,
                  child: CloseButton(
                    onPressed: () =>
                        CameraViewStateManager.of(context).onBarcodeDetected(
                      '8714100635674',
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  void _vibrateWithTheSameBarcode() async {
    final DateTime now = DateTime.now();
    if (now.difference(_lastDetectionOfTheSameBarcode!) >
        const Duration(seconds: 2)) {
      _lastDetectionOfTheSameBarcode = now;
      await HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.lightImpact();
    }
  }

  bool _isCameraFullyVisible() => widget.progress < 0.02;

  void showProduct(BuildContext topContext, Product product) {
    HomePage.of(topContext).ignoreAllEvents(true);

    final Widget header = ProductPage.buildHeader(product);
    ComputeOfflineSize(
      context: topContext,
      widget: header,
      onSizeAvailable: (Size size) {
        final DraggableScrollableLockAtTopController
            draggableScrollableController =
            DraggableScrollableLockAtTopController();

        // The fraction should allow to view the header
        // + the hint (slide up to see details)
        // + a slight padding
        final double fraction = (size.height +
                ProductHeaderTopPaddingComputation.computeMinSize(context) +
                (ProductHeaderTabBar.TAB_BAR_HEIGHT * 1.35)) /
            (MediaQuery.of(topContext).size.height -
                NavApp.of(topContext).navBarHeight);

        NavApp.of(topContext).showSheet(
          DraggableScrollableLockAtTopSheet(
            key: Key('product_${DateTime.now().millisecondsSinceEpoch}'),
            initialChildSize: fraction,
            minChildSize: fraction,
            expand: true,
            snap: true,
            controller: draggableScrollableController,
            lockAtTop: () => true,
            builder: (
              BuildContext context,
              ScrollController scrollController,
            ) {
              return ListenableProvider<
                  DraggableScrollableLockAtTopController>.value(
                value: draggableScrollableController,
                child: ChangeListener<DraggableScrollableLockAtTopController>(
                  onValueChanged: () {
                    if (draggableScrollableController.size < 0.01) {
                      NavApp.of(topContext).hideSheet();
                      HomePage.of(topContext).ignoreAllEvents(false);
                    }
                  },
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUIStyle.light,
                    child: _MagicBackgroundBottomSheet(
                      scrollController: draggableScrollableController,
                      style: DefaultTextStyle.of(topContext).style,
                      minFraction: fraction,
                      child: ProductPage.fromModalSheet(
                        product: product,
                        topSliverHeight: size.height,
                        scrollController: scrollController,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class DetectedBarcode {
  final String barcode;
  final List<Offset> corners;
  final double? width;
  final double? height;

  DetectedBarcode({
    required this.barcode,
    required this.corners,
    required this.width,
    required this.height,
  });

  bool get hasSize => width != null && height != null;
}

class _MagicBackgroundBottomSheet extends StatefulWidget {
  const _MagicBackgroundBottomSheet({
    required this.scrollController,
    required this.style,
    required this.minFraction,
    required this.child,
  });

  final DraggableScrollableLockAtTopController scrollController;
  final double minFraction;
  final TextStyle style;
  final Widget child;

  @override
  State<_MagicBackgroundBottomSheet> createState() =>
      _MagicBackgroundBottomSheetState();
}

class _MagicBackgroundBottomSheetState
    extends State<_MagicBackgroundBottomSheet> {
  //ignore: constant_identifier_names
  static const double HINT_SIZE = 50.0;

  double _topRadius = 20.0;
  double _hintOpacity = 1.0;
  double _hintSize = HINT_SIZE;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.scrollController.replaceListener(_onScroll);
  }

  void _onScroll() {
    final MediaQueryData mediaQueryData = MediaQuery.of(context);
    final double screenTopPadding = mediaQueryData.viewPadding.top;
    final double screenHeight =
        widget.scrollController.pixels / widget.scrollController.size;

    final double startPoint = screenHeight - screenTopPadding;

    _updateHint(startPoint, screenHeight);
    _updateRadius(startPoint, screenHeight);
  }

  void _updateHint(double startPoint, double screenHeight) {
    final double maxFraction = widget.minFraction + 0.1;

    final double opacity;

    if (widget.scrollController.size > maxFraction) {
      opacity = 0.0;
    } else {
      opacity = 1.0 * 1 -
          (widget.scrollController.size.progress(
            widget.minFraction,
            maxFraction,
          )).clamp(0.0, 1.0);
    }

    if (opacity != _hintOpacity) {
      setState(() => _hintOpacity = opacity);
    }

    final double hintSize;
    final double hintSizeThreshold = startPoint * 0.8;
    if (opacity > 0.0 || widget.scrollController.pixels < hintSizeThreshold) {
      hintSize = HINT_SIZE;
    } else if (widget.scrollController.pixels > startPoint) {
      hintSize = 0.0;
    } else {
      hintSize = HINT_SIZE *
          (1 -
              (widget.scrollController.pixels.progress(
                hintSizeThreshold,
                startPoint,
              )));
    }

    if (hintSize != _hintSize) {
      setState(() => _hintSize = hintSize);
    }
  }

  void _updateRadius(double startPoint, double screenHeight) {
    final double radius;

    if (widget.scrollController.pixels < startPoint) {
      radius = 20.0;
    } else {
      radius = 20 * 1 -
          (widget.scrollController.pixels.progress(
            startPoint,
            screenHeight,
          ));
    }

    if (radius != _topRadius) {
      setState(() => _topRadius = radius);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Material(
      type: MaterialType.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_topRadius),
        ),
      ),
      child: widget.child,
    );

    if (_topRadius > 0.0) {
      content = ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_topRadius),
        ),
        child: content,
      );
    }

    return OverflowBox(
      child: Column(
        children: [
          DefaultTextStyle(
            style: widget.style,
            child: GestureDetector(
              onTap: () => _onHintTapped(),
              onPanStart: (_) => _onHintTapped(),
              child: _MagicHint(
                opacity: _hintOpacity,
                height: _hintSize,
              ),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  void _onHintTapped() {
    if (widget.scrollController.size < 1.0) {
      widget.scrollController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInExpo,
      );
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }
}

class _MagicHint extends StatelessWidget {
  const _MagicHint({
    required this.height,
    required this.opacity,
  });

  final double opacity;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (height == 0.0) {
      return EMPTY_WIDGET;
    }

    final Widget chevronAnimation;
    if (opacity == 1.0) {
      chevronAnimation = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10.0,
              offset: Offset.zero,
            ),
          ],
        ),
        child: const DoubleChevronAnimation.animate(),
      );
    } else {
      chevronAnimation = const DoubleChevronAnimation.stopped();
    }

    return SizedBox(
      height: height,
      child: Opacity(
        opacity: opacity,
        child: DefaultTextStyle(
            style: const TextStyle(),
            child: IconTheme(
              data: const IconThemeData(color: Colors.white, size: 18.0),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 20.0,
                ),
                child: Row(
                  children: [
                    chevronAnimation,
                    const Expanded(
                      child: Text(
                        'Glissez vers le haut pour voir les détails',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w500, shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 10.0,
                            offset: Offset(0.0, 2.0),
                          )
                        ]),
                      ),
                    ),
                    chevronAnimation,
                  ],
                ),
              ),
            )),
      ),
    );
  }
}

/// The message overlay is only visible when the [CameraViewStateManager] emits
/// a [CameraViewNoBarcodeState] or a [CameraViewInvalidBarcodeState].
class _MessageOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SheetVisibilityNotifier>(
      builder: (BuildContext context, SheetVisibilityNotifier notifier, _) {
        return Selector<CameraViewStateManager, CameraViewState>(
          selector: (_, CameraViewStateManager state) => state.value,
          shouldRebuild: (CameraViewState previous, CameraViewState next) {
            return next is CameraViewNoBarcodeState ||
                next is CameraViewInvalidBarcodeState ||
                previous is CameraViewNoBarcodeState ||
                previous is CameraViewInvalidBarcodeState;
          },
          builder: (BuildContext context, CameraViewState state, _) {
            return switch (state) {
              CameraViewNoBarcodeState _ => const CameraMessageOverlay(
                  message: 'Scannez un produit en approchant son code-barres',
                ),
              CameraViewInvalidBarcodeState(barcode: final String barcode) =>
                CameraMessageOverlay(
                  message:
                      'Nous avons détecté le code $barcode, mais ce n’est pas un code-barres valide',
                ),
              _ => EMPTY_WIDGET,
            };
          },
        );
      },
    );
  }
}

class _OpaqueOverlay extends StatelessWidget {
  const _OpaqueOverlay({
    required this.isCameraFullyVisible,
    required this.progress,
  });

  final bool isCameraFullyVisible;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: isCameraFullyVisible,
      child: Opacity(
        opacity: progress,
        child: const ColoredBox(
          color: Colors.black,
        ),
      ),
    );
  }
}

class CustomScannerController {
  final MobileScannerController _controller;
  final _TorchState _torchState;

  bool _isStarted = false;
  bool _isStarting = false;
  bool _isClosing = false;
  bool _isClosed = false;

  CustomScannerController({
    required MobileScannerController controller,
  })  : _controller = controller,
        _torchState = _TorchState() {
    _detectTorch();
  }

  Future<void> start() async {
    if (isStarted || _isStarting || isClosing) {
      return;
    }

    _isStarting = true;
    _isClosed = false;
    try {
      await _controller.start();
      _isStarted = true;

      if (isTorchOn) {
        // Slight delay, because it doesn't always work if called immediately
        Future.delayed(const Duration(milliseconds: 250), () {
          turnTorchOn();
        });
      }
      _isStarting = false;
    } catch (_) {}
  }

  void onPause() {
    _isStarted = false;
    _isStarting = false;
    _isClosing = false;
    _isClosed = false;
  }

  bool get isStarted => _isStarted;

  bool get isClosing => _isClosing;

  bool get isClosed => _isClosed;

  Future<void> stop() async {
    if (isClosed || isClosing || _isStarting) {
      return;
    }

    _isClosing = true;
    _isStarting = false;
    _isStarted = false;
    try {
      await _controller.stop();
      _isClosing = false;
      _isClosed = true;
    } catch (_) {}
  }

  bool get hasTorch => _torchState.value != null;

  ValueNotifier<bool?> get hasTorchState => _torchState;

  bool get isTorchOn => _torchState.value == true;

  void turnTorchOff() {
    if (isTorchOn) {
      _controller.toggleTorch();
      _torchState.value = false;
    }
  }

  void turnTorchOn() {
    if (!isTorchOn) {
      _controller.toggleTorch();
      _torchState.value = true;
    }
  }

  void toggleCamera() {
    _controller.switchCamera();
    if (_controller.facing == CameraFacing.front) {
      _torchState.value = null;
    } else if (_controller.facing == CameraFacing.front) {
      _torchState.value = false;
    }
  }

  Future<void> _detectTorch() async {
    try {
      final bool isTorchAvailable = await TorchLight.isTorchAvailable();
      if (isTorchAvailable) {
        _torchState.value = false;
      } else {
        _torchState.value = null;
      }
    } on Exception catch (_) {}
  }
}

class _TorchState extends ValueNotifier<bool?> {
  _TorchState({bool? value}) : super(value);
}
