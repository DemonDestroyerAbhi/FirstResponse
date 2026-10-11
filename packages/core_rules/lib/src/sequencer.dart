import 'model.dart';

enum StepKind {
  /// The record holds a wrong value and must be corrected.
  fix,

  /// The record copies from one that was just fixed, so it must be updated
  /// again or it will keep the old value.
  resync,
}

class SequenceStep {
  final RecordType record;
  final StepKind kind;

  /// For [StepKind.resync], the fixed records this one copies from.
  final List<String> because;

  const SequenceStep(this.record, this.kind, [this.because = const []]);

  @override
  String toString() =>
      '${kind.name}:${record.id}'
      '${because.isEmpty ? '' : ' <- ${because.join(',')}'}';
}

class RecordGraphException implements Exception {
  final String message;
  const RecordGraphException(this.message);
  @override
  String toString() => 'RecordGraphException: $message';
}

/// Orders fixes across records so nothing is fixed before its source of truth.
///
/// Fixing EPFO KYC before Aadhaar wastes a trip: EPFO validates against
/// Aadhaar, so the request bounces until Aadhaar is right. This sequencer
/// puts upstream fixes first and adds re-sync steps for every record
/// downstream of a fix.
class FixSequencer {
  final Map<String, RecordType> records;

  /// Every record in dependency order, sources of truth first.
  late final List<String> _order = _topologicalOrder();

  FixSequencer(Iterable<RecordType> records)
    : records = {for (final r in records) r.id: r} {
    for (final r in this.records.values) {
      for (final up in r.copiesFrom) {
        if (!this.records.containsKey(up)) {
          throw RecordGraphException('${r.id} copies from unknown record $up');
        }
      }
    }
    _order; // Fail fast on cycles.
  }

  /// Steps to fix [broken] records, in the order they should be done.
  ///
  /// [involved] limits re-sync steps to records that matter for this case
  /// (e.g. only the records a pension depends on). When null, every
  /// downstream record is included.
  List<SequenceStep> plan(Set<String> broken, {Set<String>? involved}) {
    for (final id in broken) {
      if (!records.containsKey(id)) {
        throw RecordGraphException('Unknown record $id');
      }
    }
    final touched = <String, List<String>>{}; // record -> fixed ancestors
    final steps = <SequenceStep>[];
    for (final id in _order) {
      final r = records[id]!;
      final fixedUpstream = [
        for (final up in r.copiesFrom)
          if (broken.contains(up) || touched.containsKey(up)) up,
      ];
      if (broken.contains(id)) {
        steps.add(SequenceStep(r, StepKind.fix));
        touched[id] = const [];
      } else if (fixedUpstream.isNotEmpty) {
        touched[id] = fixedUpstream;
        if (involved == null || involved.contains(id)) {
          // Name only reasons the user can see as steps; fall back to the
          // hidden ones when the change came through a record left out.
          final shown = fixedUpstream
              .where((up) => steps.any((s) => s.record.id == up))
              .toList();
          steps.add(
            SequenceStep(
              r,
              StepKind.resync,
              shown.isEmpty ? fixedUpstream : shown,
            ),
          );
        }
      }
    }
    return steps;
  }

  /// Kahn's algorithm with ties broken by id, so output is stable.
  List<String> _topologicalOrder() {
    final indegree = {for (final id in records.keys) id: 0};
    final downstream = {for (final id in records.keys) id: <String>[]};
    for (final r in records.values) {
      for (final up in r.copiesFrom) {
        indegree[r.id] = indegree[r.id]! + 1;
        downstream[up]!.add(r.id);
      }
    }
    final ready = [
      for (final e in indegree.entries)
        if (e.value == 0) e.key,
    ]..sort();
    final order = <String>[];
    while (ready.isNotEmpty) {
      final id = ready.removeAt(0);
      order.add(id);
      for (final d in downstream[id]!) {
        indegree[d] = indegree[d]! - 1;
        if (indegree[d] == 0) {
          ready
            ..add(d)
            ..sort();
        }
      }
    }
    if (order.length != records.length) {
      final stuck = records.keys.where((id) => !order.contains(id)).toList()
        ..sort();
      throw RecordGraphException('Cycle among records: ${stuck.join(', ')}');
    }
    return order;
  }
}
