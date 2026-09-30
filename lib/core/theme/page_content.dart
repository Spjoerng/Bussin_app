import 'package:flutter/material.dart';

/// Keeps reading and editing comfortable on tablets, and clear of system UI.
class PageContent extends StatelessWidget {
  const PageContent({super.key, required this.child, this.maxWidth = 840});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}
