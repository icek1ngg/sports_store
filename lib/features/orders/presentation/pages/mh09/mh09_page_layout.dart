import 'package:flutter/material.dart';

/// Reserves independent content-sized header, scroll body and safe footer areas.
class Mh09PageLayout extends StatelessWidget {
  const Mh09PageLayout({
    required this.header,
    required this.body,
    this.footer,
    super.key,
  });

  final Widget header;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: footer == null
          ? null
          : SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .35,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: footer,
                  ),
                ),
              ),
            ),
      body: SafeArea(
        child: Column(
          children: [
            header,
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
