import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/state/epoch_cache.dart';
import 'package:sports_store/core/state/session_scope.dart';

void main() {
  const scope = SessionScope(userId: 'A', role: 'customer', generation: 1);
  test('TX-26: epoch, query and latest request reject obsolete reads', () {
    final cache = EpochCache(scope);
    final first = cache.begin('order');
    expect(cache.accept(first, 'delivering'), isTrue);
    final late = cache.begin('order');
    cache.invalidate('order');
    expect(cache.accept(late, 'preparing'), isFalse);
    expect(cache.read<String>('order')!.data, 'delivering');
    expect(cache.read<String>('order')!.stale, isTrue);
    final oldQuery = cache.begin('order', queryGeneration: 1);
    final newQuery = cache.begin('order', queryGeneration: 2);
    expect(cache.accept(oldQuery, 'old filter'), isFalse);
    expect(cache.accept(newQuery, 'new filter'), isTrue);
    final oldRead = cache.begin('order', queryGeneration: 2);
    final latestRead = cache.begin('order', queryGeneration: 2);
    expect(cache.accept(latestRead, 'delivered'), isTrue);
    expect(cache.accept(oldRead, 'preparing'), isFalse);
  });
  test('TX-08/09: disposal and expiry hide data and reject callbacks', () {
    final cache = EpochCache(scope);
    final token = cache.begin('private');
    cache.accept(token, 'private A');
    cache.blockSession();
    expect(cache.read<String>('private'), isNull);
    expect(cache.accept(token, 'late A'), isFalse);
    final other = EpochCache(
      const SessionScope(userId: 'B', role: 'customer', generation: 2),
    );
    expect(other.accept(token, 'A leak'), isFalse);
    expect(other.read<String>('private'), isNull);
    cache.dispose();
    expect(cache.accept(cache.begin('private'), 'late'), isFalse);
  });
  test('unresolved role is fail closed, not a privileged default', () {
    final cache = EpochCache(
      const SessionScope(
        userId: 'A',
        role: 'manager',
        generation: 1,
        roleResolved: false,
      ),
    );
    expect(cache.accept(cache.begin('x'), 'private'), isFalse);
    expect(cache.read<String>('x'), isNull);
  });
}
