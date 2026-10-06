import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _BaseProjectPage()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

// Temporary app shell; business routes will be added by their feature owners.
class _BaseProjectPage extends StatelessWidget {
  const _BaseProjectPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sports Store')),
      body: const Center(child: Text('Ứng dụng đang được xây dựng.')),
    );
  }
}
