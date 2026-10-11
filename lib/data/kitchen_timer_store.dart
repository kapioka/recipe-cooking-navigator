import '../domain/kitchen_timer.dart';

/// Process-local Phase 3 state. Persistence and recovery belong to Phase 4.
class KitchenTimerStore {
  List<KitchenTimer> _timers = const [];

  List<KitchenTimer> get timers => _timers;

  void replaceAll(Iterable<KitchenTimer> timers) {
    final next = List<KitchenTimer>.unmodifiable(timers);
    if (next.map((timer) => timer.id).toSet().length != next.length) {
      throw ArgumentError('Timer IDs must be unique.');
    }
    _timers = next;
  }
}
