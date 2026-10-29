import 'package:flutter/material.dart';

import 'mh07_preview_data.dart';
import 'mh08_manager_repository.dart';
import 'mh08_preview_environment.dart';

class Mh08PreviewControls extends StatelessWidget
    implements PreferredSizeWidget {
  const Mh08PreviewControls({
    required this.environment,
    required this.onNextPageError,
    super.key,
  });
  final Mh08PreviewEnvironment environment;
  final VoidCallback onNextPageError;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: 48,
    title: const Text(
      'DEMO UI · dữ liệu kiểm thử',
      style: TextStyle(fontSize: 12),
    ),
    actions: [
      PopupMenuButton<String>(
        tooltip: 'Chọn màn hình',
        initialValue: environment.screen,
        onSelected: environment.selectScreen,
        itemBuilder: (_) => ['MH07', 'MH08']
            .map((screen) => PopupMenuItem(value: screen, child: Text(screen)))
            .toList(),
      ),
      PopupMenuButton<Mh08PreviewScenario>(
        tooltip: 'Chọn trạng thái',
        initialValue: environment.scenario,
        onSelected: environment.selectScenario,
        itemBuilder: (_) => Mh08PreviewScenario.values
            .where(
              (scenario) =>
                  environment.managerActive ||
                  PreviewScenario.values.any((v) => v.name == scenario.name),
            )
            .map(
              (scenario) => PopupMenuItem(
                value: scenario,
                key: ValueKey('preview-scenario-${scenario.name}'),
                child: Text(
                  scenario == Mh08PreviewScenario.sessionUnavailable
                      ? 'session unavailable'
                      : scenario.name,
                ),
              ),
            )
            .toList(),
      ),
      if (environment.managerActive)
        IconButton(
          tooltip: 'DEMO: lỗi trang tiếp theo',
          onPressed:
              environment.scope.role == 'manager' &&
                  environment.scope.canReadPrivateData
              ? onNextPageError
              : null,
          icon: const Icon(Icons.error_outline),
        ),
    ],
  );
}
