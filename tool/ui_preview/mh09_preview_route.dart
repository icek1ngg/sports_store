import 'package:flutter/material.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';

import 'mh08_preview_environment.dart';
import 'mh09_preview_scenario.dart';

/// Debug controls live only on the pushed MH09 route, outside production UI.
class Mh09PreviewRoute extends StatelessWidget {
  const Mh09PreviewRoute({
    required this.environment,
    required this.orderId,
    required this.showControls,
    super.key,
  });
  final Mh08PreviewEnvironment environment;
  final String orderId;
  final bool showControls;

  @override
  Widget build(BuildContext context) {
    final page = ManagerOrderDetailsPage(
      orderId: orderId,
      enablePolling: false,
    );
    if (!showControls) return page;
    return ListenableBuilder(
      listenable: environment.mh09,
      builder: (context, _) => Column(
        children: [
          SafeArea(
            bottom: false,
            child: Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'DEMO MH09 · ${environment.mh09.scenario.name}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  PopupMenuButton<Mh09PreviewScenario>(
                    tooltip: 'MH09: chọn kịch bản',
                    initialValue: environment.mh09.scenario,
                    onSelected: environment.selectMh09Scenario,
                    itemBuilder: (_) => Mh09PreviewScenario.values
                        .map(
                          (scene) => PopupMenuItem(
                            value: scene,
                            key: ValueKey('mh09-preview-${scene.name}'),
                            child: Text(scene.name),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: page,
            ),
          ),
        ],
      ),
    );
  }
}
