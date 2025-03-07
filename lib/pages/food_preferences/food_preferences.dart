import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smoothapp_poc/utils/system_ui.dart';
import 'package:smoothapp_poc/utils/widgets/will_pop_scope.dart';

bool foodPreferencesDefined = false;

class FoodPreferencesPage extends StatefulWidget {
  const FoodPreferencesPage({super.key});

  @override
  State<FoodPreferencesPage> createState() => _FoodPreferencesPageState();
}

class _FoodPreferencesPageState extends State<FoodPreferencesPage> {
  int currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUIStyle.dark,
      child: Scaffold(
        body: WillPopScope2(
          onWillPop: () async {
            if (currentPage > 0) {
              setState(() => currentPage--);
              return (false, null);
            }
            return (true, null);
          },
          child: GestureDetector(
            onTapDown: (TapDownDetails details) {
              final Size size = MediaQuery.sizeOf(context);
              if (details.localPosition.dy > size.height * 0.9) {
                if (details.localPosition.dx < size.width * 0.4) {
                  if (currentPage > 0) {
                    setState(() => currentPage--);
                  } else {
                    Navigator.of(context).pop(false);
                  }
                }
                if (details.localPosition.dx > size.width * 0.6) {
                  if (currentPage < 9) {
                    setState(() => currentPage++);
                  } else {
                    foodPreferencesDefined = true;
                    Navigator.of(context).pop(true);
                  }
                }
              }
            },
            child: SafeArea(
              top: false,
              bottom: Platform.isAndroid,
              child: SizedBox.expand(
                child: Image.asset(
                  'assets/images/foodprefs_${currentPage + 1}.webp',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
