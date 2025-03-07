import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:smoothapp_poc/navigation.dart';
import 'package:smoothapp_poc/pages/homepage/camera/expandable_view/expandable_camera.dart';
import 'package:smoothapp_poc/pages/homepage/camera/view/camera_state_manager.dart';
import 'package:smoothapp_poc/pages/homepage/camera/view/ui/camera_view.dart';
import 'package:smoothapp_poc/pages/homepage/homepage_products_counter.dart';
import 'package:smoothapp_poc/pages/homepage/list/homepage_categories.dart';
import 'package:smoothapp_poc/pages/homepage/list/homepage_guides_list.dart';
import 'package:smoothapp_poc/pages/homepage/list/homepage_news_list.dart';
import 'package:smoothapp_poc/pages/homepage/list/homepage_scanned_list.dart';
import 'package:smoothapp_poc/pages/search_page/search_page.dart';
import 'package:smoothapp_poc/resources/app_icons.dart' as icons;
import 'package:smoothapp_poc/utils/physics.dart';
import 'package:smoothapp_poc/utils/provider_utils.dart';
import 'package:smoothapp_poc/utils/system_ui.dart';
import 'package:smoothapp_poc/utils/ui_utils.dart';
import 'package:smoothapp_poc/utils/widgets/search_bar/search_bar.dart';
import 'package:visibility_detector/visibility_detector.dart';

//ignore_for_file: constant_identifier_names
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const double CAMERA_PEAK = 0.4;
  static const double BORDER_RADIUS = 30.0;
  static const double APP_BAR_HEIGHT = 160.0;
  static const double HORIZONTAL_PADDING = 24.0;
  static const double TOP_ICON_PADDING =
      kToolbarHeight - kMinInteractiveDimension;

  @override
  State<HomePage> createState() => HomePageState();

  static HomePageState of(BuildContext context) {
    return context.read<HomePageState>();
  }
}

class HomePageState extends State<HomePage> {
  final Key _screenKey = UniqueKey();

  // Lazy values (used to minimize the time required on each frame)
  double? _cameraPeakHeight;
  double? _scrollPositionBeforePause;

  late ScrollController _controller;
  late CustomScannerController _cameraController;
  late final AppLifecycleListener _lifecycleListener;

  bool _ignoreAllEvents = false;
  ScrollStartNotification? _scrollStartNotification;
  ScrollStartNotification? _scrollInitialStartNotification;
  ScrollMetrics? _userInitialScrollMetrics;
  VerticalSnapScrollPhysics? _physics;
  ScrollDirection _direction = ScrollDirection.forward;
  bool _screenVisible = false;

  @override
  void initState() {
    super.initState();

    _controller = ScrollController();
    _cameraController = CustomScannerController(
      controller: MobileScannerController(
        autoStart: false,
      ),
    );
    _lifecycleListener = AppLifecycleListener(
      onPause: _onPause,
      onResume: _onResume,
    );

    _setInitialScroll();
  }

  void _onPause() {
    if (_controller.hasClients) {
      _scrollPositionBeforePause = _controller.offset;
      _cameraController.onPause();
    }
  }

  void _onResume() {
    if (_scrollPositionBeforePause != null &&
        isCameraVisible(
          offset: _scrollPositionBeforePause!,
        )) {
      _cameraController.start();
    }
  }

  void _setInitialScroll() {
    onNextFrame(() {
      final double offset = _initialOffset;

      if (offset <= 0) {
        // The MediaQuery is not yet ready (reproducible in production)
        _setInitialScroll();
      } else {
        _physics = VerticalSnapScrollPhysics(
          steps: [
            0.0,
            cameraPeak,
            cameraHeight,
          ],
          lastStepBlocking: true,
        );
        _controller.jumpTo(_initialOffset);
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => CameraViewStateManager(),
        ),
        Provider.value(value: this),
        ChangeNotifierProvider.value(value: _controller),
      ],
      child: ValueListener<OnTabChangedNotifier, HomeTabs>(
        onValueChanged: (HomeTabs tab) {
          if (tab == HomeTabs.scanner) {
            if (NavApp.of(context).hasSheet) {
              NavApp.of(context).hideSheet();
              collapseCamera();
            } else if (!isCameraFullyVisible) {
              expandCamera();
            } else {
              collapseCamera();
            }
          }
        },
        child: VisibilityDetector(
          key: _screenKey,
          onVisibilityChanged: (VisibilityInfo visibility) {
            _screenVisible = visibility.visibleFraction > 0;
            _onScreenVisibilityChanged(_screenVisible);
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: NotificationListener(
              onNotification: (Object? notification) {
                if (_ignoreAllEvents) {
                  return false;
                }

                if (notification is ScrollStartNotification) {
                  if (notification.dragDetails != null) {
                    _scrollInitialStartNotification = _scrollStartNotification;
                  } else {
                    _scrollInitialStartNotification = null;
                  }

                  _scrollStartNotification = notification;
                } else if (notification is UserScrollNotification) {
                  _direction = notification.direction;

                  if (notification.direction != ScrollDirection.idle) {
                    _userInitialScrollMetrics = notification.metrics;
                  }
                } else if (notification is ScrollEndNotification) {
                  // Ignore if this is just a tap or a non-user event
                  // (drag detail == null)
                  if (notification.metrics.axis != Axis.vertical ||
                      notification.dragDetails == null ||
                      (_scrollInitialStartNotification == null &&
                          _scrollStartNotification?.metrics ==
                              notification.metrics)) {
                    return false;
                  }

                  _onScrollEnded(notification);
                } else if (notification is ScrollUpdateNotification) {
                  if (notification.metrics.axis != Axis.vertical) {
                    return false;
                  }
                  _onScrollUpdate(notification);
                }
                return false;
              },
              child: Builder(builder: (BuildContext context) {
                return CustomScrollView(
                  physics: _ignoreAllEvents
                      ? const NeverScrollableScrollPhysics()
                      : _physics,
                  controller: _controller,
                  slivers: [
                    ExpandableCamera(
                      controller: _cameraController,
                      height: MediaQuery.sizeOf(context).height -
                          kBottomNavigationBarHeight -
                          MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    ExpandableSearchAppBar(
                      onFieldTapped: () {
                        HomePage.of(context).showAppBar(
                            onAppBarVisible: () async {
                          SearchPageResult? res =
                              await SearchPage.open(context);

                          if (res == SearchPageResult.openCamera &&
                              context.mounted) {
                            HomePage.of(context).expandCamera(
                              duration: const Duration(milliseconds: 1500),
                            );
                          }
                        });
                      },
                      actionIcon: const icons.Barcode(),
                      actionSemantics: 'Afficher le lecteur de code-barres',
                      onActionButtonClicked: () {
                        HomePage.of(context).expandCamera(
                          duration: const Duration(milliseconds: 1500),
                        );
                      },
                      footer: HomePageProductCounter(
                        textScaler: MediaQuery.textScalerOf(context),
                      ),
                    ),
                    const HomePageCategories(),
                    const HistoryList(),
                    const MostScannedProducts(),
                    const GuidesList(),
                    const NewsList(),
                    SliverPadding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.viewPaddingOf(context).bottom,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  double get cameraHeight =>
      MediaQuery.sizeOf(context).height -
      MediaQuery.viewPaddingOf(context).bottom -
      kBottomNavigationBarHeight;

  double get cameraPeak => _initialOffset;

  double get _appBarHeight =>
      ExpandableSearchAppBar.HEIGHT + MediaQuery.paddingOf(context).top;

  double get _initialOffset => cameraHeight * (1 - HomePage.CAMERA_PEAK);

  bool get isCameraFullyVisible => _controller.offset == 0.0;

  bool isCameraVisible({double? offset}) {
    if (_screenVisible && !NavApp.of(context).isSheetFullyVisible) {
      double position = (offset ?? _controller.offset);
      return position >= 0.0 && position < cameraHeight;
    }
    return false;
  }

  bool get isExpanded => _controller.offset < _initialOffset;

  void ignoreAllEvents(bool value) {
    setState(() => _ignoreAllEvents = value);
  }

  void expandCamera({Duration? duration}) {
    _physics?.ignoreNextScroll = true;
    _controller.animateTo(
      0,
      duration: duration ?? const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  void collapseCamera() {
    if (_controller.offset == _initialOffset) {
      return;
    }

    ignoreAllEvents(false);
    _physics?.ignoreNextScroll = true;
    _controller.animateTo(
      _initialOffset,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  void showAppBar({VoidCallback? onAppBarVisible}) {
    const Duration duration = Duration(milliseconds: 200);
    _controller.animateTo(
      MediaQuery.sizeOf(context).height -
          MediaQuery.viewPaddingOf(context).bottom -
          kBottomNavigationBarHeight,
      duration: duration,
      curve: Curves.easeOutCubic,
    );

    if (onAppBarVisible != null) {
      Future.delayed(duration, () => onAppBarVisible.call());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _lifecycleListener.dispose();
    super.dispose();
  }

  /// On scroll, update:
  /// - The status bar theme (light/dark)
  /// - Start/stop the camera
  /// - Update the type of the settings icon
  void _onScrollUpdate(ScrollUpdateNotification notification) {
    if (_controller.offset.ceilToDouble() < cameraHeight) {
      SystemChrome.setSystemUIOverlayStyle(SystemUIStyle.light);
      if (!_cameraController.isStarted) {
        _cameraController.start();
      }
    } else {
      SystemChrome.setSystemUIOverlayStyle(SystemUIStyle.dark);
      _cameraController.stop();
    }
  }

  /// When a scroll is finished, animate the content to the correct position
  void _onScrollEnded(ScrollEndNotification notification) {
    final double cameraViewHeight = cameraHeight;
    final double scrollPosition = notification.metrics.pixels;

    final List<double> steps = [0.0, cameraPeak, cameraViewHeight];
    if (steps.contains(scrollPosition) && _userInitialScrollMetrics != null) {
      double fixedPosition = VerticalSnapScrollPhysics.fixInconsistency(
        steps,
        scrollPosition,
        _userInitialScrollMetrics!.pixels,
      );

      if (fixedPosition != scrollPosition &&
          _scrollInitialStartNotification == null) {
        // If the user scrolls really quickly, he/she can miss a step
        Future.delayed(Duration.zero, () {
          _controller.jumpTo(fixedPosition);
        });
      }
      return;
    } else if (scrollPosition.roundToDouble() >= cameraViewHeight ||
        (_direction == ScrollDirection.idle &&
            _scrollInitialStartNotification == null)) {
      return;
    }

    final double position;
    _cameraPeakHeight ??= cameraViewHeight * (1 - HomePage.CAMERA_PEAK);

    if (scrollPosition < (_cameraPeakHeight!)) {
      if (_direction == ScrollDirection.reverse) {
        position = 0.0;
      } else {
        position = _initialOffset;
      }
    } else if (scrollPosition < cameraViewHeight) {
      if (_direction == ScrollDirection.reverse) {
        position = _cameraPeakHeight!;
      } else {
        position = cameraViewHeight;
      }
    } else if (_direction == ScrollDirection.reverse) {
      position = cameraViewHeight + _appBarHeight;
    } else {
      position = cameraViewHeight;
    }

    Future.delayed(Duration.zero, () {
      _controller.animateTo(
        position,
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 500),
      );
    });
  }

  void _onScreenVisibilityChanged(bool visible) {
    if (visible && isCameraVisible()) {
      _cameraController.start();
    } else {
      _cameraController.stop();
    }
  }
}

class SliverListBldr extends StatelessWidget {
  const SliverListBldr({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          return Padding(
            padding: const EdgeInsets.only(left: 10.0, bottom: 20, right: 10),
            child: SizedBox(
              height: 200,
              width: MediaQuery.of(context).size.width,
              child: const Text('Text'),
            ),
          );
        },
        childCount: 20,
      ),
    );
  }
}
