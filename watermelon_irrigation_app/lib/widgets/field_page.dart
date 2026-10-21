import 'package:flutter/material.dart';

import '../state/field_controller.dart';
import '../theme/app_theme.dart';
import 'state_views.dart';

/// Shared page frame: handles loading, empty and error states once,
/// so each screen only describes its ready content.
class FieldPage extends StatelessWidget {
  const FieldPage({super.key, required this.title, required this.builder});

  final String title;
  final List<Widget> Function(BuildContext context, FieldController controller) builder;

  @override
  Widget build(BuildContext context) {
    final c = FieldScope.of(context);
    final Widget body = switch (c.status) {
      LoadStatus.loading => const LoadingView(),
      LoadStatus.error => MessageView(
          icon: Icons.cloud_off,
          iconColor: Palette.flesh,
          title: 'Field data could not be loaded',
          message: c.errorMessage,
          actionLabel: 'Try again',
          onAction: c.load,
        ),
      LoadStatus.empty => MessageView(
          icon: Icons.inbox_outlined,
          title: 'No field data available yet.',
          message: 'Readings will appear here after the first observation is recorded.',
          actionLabel: 'Check again',
          onAction: c.load,
        ),
      LoadStatus.ready => RefreshIndicator(
          color: Palette.rind,
          onRefresh: c.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: builder(context, c),
          ),
        ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(top: false, child: body),
    );
  }
}
