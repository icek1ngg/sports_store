import 'package:flutter/material.dart';

import 'mh08_header.dart';

/// Keeps the feed usable when accessibility or the keyboard reduces height.
class Mh08PageLayout extends StatelessWidget {
  const Mh08PageLayout({
    required this.controls,
    required this.feed,
    this.onRefresh,
    super.key,
  });

  final Widget controls;
  final Widget feed;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: Mh08KeyboardVisibility(
        visible: keyboardVisible,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                Flexible(
                  flex: 0,
                  fit: FlexFit.loose,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .55,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Mh08Header(onRefresh: onRefresh),
                          controls,
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: feed),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Derived before Scaffold consumes insets; never resizes or adds padding.
class Mh08KeyboardVisibility extends InheritedWidget {
  const Mh08KeyboardVisibility({
    required this.visible,
    required super.child,
    super.key,
  });

  final bool visible;

  static bool isVisibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<Mh08KeyboardVisibility>()
          ?.visible ??
      MediaQuery.viewInsetsOf(context).bottom > 0;

  @override
  bool updateShouldNotify(Mh08KeyboardVisibility oldWidget) =>
      visible != oldWidget.visible;
}
