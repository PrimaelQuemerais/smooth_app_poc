import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:smoothapp_poc/main.dart';

class ExpandableAppBar extends StatelessWidget {
  static const double HEIGHT = 145.0;
  static const EdgeInsetsDirectional CONTENT_PADDING =
      EdgeInsetsDirectional.only(
    start: 20.0,
    end: 20.0,
  );

  const ExpandableAppBar({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      delegate: SliverSearchAppBar(
        topPadding: MediaQuery.paddingOf(context).top,
      ),
      pinned: true,
    );
  }
}

class SliverSearchAppBar extends SliverPersistentHeaderDelegate {
  const SliverSearchAppBar({
    required this.topPadding,
  });

  final double topPadding;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Selector<ScrollController, double>(
      selector: (BuildContext context, ScrollController controller) {
        final double position = controller.offset;
        final HomePageState homePageState = HomePage.of(context);
        final double cameraHeight = homePageState.cameraHeight;
        final double cameraPeak = homePageState.cameraPeak;

        if (position >= cameraHeight) {
          return 1.0;
        } else if (position < cameraPeak) {
          return 0.0;
        } else {
          return (position - cameraPeak) / (cameraHeight - cameraPeak);
        }
      },
      shouldRebuild: (double previous, double next) {
        return previous != next;
      },
      builder: (BuildContext context, double progress, _) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xffffc589),
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(HomePageState.BORDER_RADIUS),
            ),
          ),
          padding: ExpandableAppBar.CONTENT_PADDING,
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Logo(
                  progress: progress,
                ),
                SearchBar(
                  scannerButtonVisibility: progress,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double computeLogoProgress(double shrinkOffset) {
    return ((shrinkOffset / minExtent) / 0.13).clamp(0.0, 1.0);
  }

  @override
  double get maxExtent => ExpandableAppBar.HEIGHT + topPadding;

  @override
  double get minExtent => ExpandableAppBar.HEIGHT + topPadding;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

class Logo extends StatelessWidget {
  const Logo({required this.progress, super.key});

  static final double FULL_WIDTH = 345.0;
  static final double MIN_HEIGHT = 35.0;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        double width = constraints.maxWidth;
        double imageWidth = FULL_WIDTH;

        if (imageWidth > width * 0.7) {
          imageWidth = width * 0.7;
        }

        return Container(
          width: imageWidth,
          height: math.max(60.0 * (1 - progress), MIN_HEIGHT),
          margin: EdgeInsetsDirectional.only(
            start: math.max((1 - progress) * ((width - imageWidth) / 2), 10.0),
          ),
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: imageWidth,
            child: SvgPicture.asset(
              'assets/images/logo.svg',
              width: imageWidth,
              height: 60.0,
              alignment: AlignmentDirectional.centerStart,
            ),
          ),
        );
      }),
    );
  }
}

class SearchBar extends StatefulWidget {
  const SearchBar({
    required this.scannerButtonVisibility,
    super.key,
  });

  final double scannerButtonVisibility;

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  final FocusNode _searchFocusNode = FocusNode();

  /// A Focus Node only used to hide the keyboard when we go up.
  final FocusNode _buttonFocusNode = FocusNode();

  /// To prevent unwanted unfocuses, during this delay, we ignore all events.
  DateTime? _ignoreFocusChange;

  @override
  Widget build(BuildContext context) {
    /// When we go up and the keyboard is visible, we move the focus to the
    /// barcode button, just to hide the keyboard.
    if (widget.scannerButtonVisibility < 1.0 &&
        _searchFocusNode.hasFocus &&
        _ignoreFocusChange != null &&
        DateTime.now().isAfter(_ignoreFocusChange!)) {
      _buttonFocusNode.requestFocus();
    }

    return SizedBox(
      height: 55.0,
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              textAlignVertical: TextAlignVertical.center,
              onTap: () {
                _ignoreFocusChange = DateTime.now().add(
                  const Duration(milliseconds: 500),
                );
                HomePage.of(context).showAppBar();
                _searchFocusNode.requestFocus();
              },
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Rechercher un produit ou un code-barres',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: const BorderSide(color: Color(0xFFFF8714)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: const BorderSide(color: Color(0xFFFF8714)),
                ),
              ),
            ),
          ),
          SizedBox.square(
            dimension: (55.0 + 8.0) * widget.scannerButtonVisibility,
            child: Focus(
              focusNode: _buttonFocusNode,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 8.0),
                child: IconButton(
                  onPressed: () {
                    HomePage.of(context).expandCamera(
                      duration: const Duration(milliseconds: 1500),
                    );
                  },
                  icon: SvgPicture.asset('assets/images/barcode.svg'),
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.all(Colors.white),
                    side: MaterialStateProperty.all(
                      const BorderSide(color: Color(0xFFFF8714)),
                    ),
                    shape: MaterialStateProperty.all(
                      const CircleBorder(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _buttonFocusNode.dispose();
    super.dispose();
  }
}
