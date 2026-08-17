/// The vocabulary of the domain (ADR §4.3), in one file because these are
/// read by every layer: Drift stores them, repositories map them, cubits
/// switch on them, and ARB localizes their labels.
///
/// **Stored by `name`, not by index.** A text column survives someone
/// reordering an enum; an integer column silently reinterprets every existing
/// row. Postgres mirrors these as enum types with the same labels (ADR §5.2).
///
/// Adding a case is a migration-free change *for reads* only if every
/// `switch` over it stays exhaustive — which is why none of them carry a
/// `default`.
library;

/// Movement pattern. The axis volume is balanced on, and what Insights groups
/// by when it catches "the quiet drift away from posterior chain work"
/// (ADR §11.2).
enum MovementPattern {
  hinge,
  squat,
  push,
  pull,
  carry,
  rotation,

  /// **Added to the ADR §4.3 list.** Anti-extension trunk work — planks, dead
  /// bugs, ab wheel, hanging leg raises — has no honest home among the other
  /// eight. `rotation` covers anti-rotation only, and filing a plank under
  /// `carry` would poison the volume-by-pattern chart it exists to feed.
  core,

  plyo,
  conditioning,
  mobility,
}

/// The section of the body an exercise trains — how the catalog picker groups
/// itself, and how a lifter actually thinks about their week ("chest day").
///
/// Deliberately *not* [MovementPattern]. A pattern is an analytical axis for
/// balancing volume, which is why Insights groups by it; a section is how
/// someone searching for "incline press" expects a list to be organised. Both
/// are stored, because collapsing them would cost one of the two jobs.
///
/// Declaration order is display order in the picker.
enum BodySection {
  chest,
  upperBack,
  lowerBack,
  shoulders,
  arms,
  core,
  glutes,
  legs,
  fullBody,
  cardio,
  mobility;

  /// Files an exercise from the data the catalog already carries.
  ///
  /// Conditioning and mobility answer to their pattern rather than to a
  /// muscle: a treadmill's `legs` is true but filing it under Legs next to
  /// squats is not what anyone is looking for.
  ///
  /// Everything else keys off the **first** primary muscle, which the seed
  /// orders most-primary-first. Unknown or empty falls back to [fullBody]
  /// rather than throwing — a catalog row from a newer version must not crash
  /// an older picker.
  static BodySection forExercise({
    required MovementPattern pattern,
    required List<String> primaryMuscles,
  }) {
    if (pattern == MovementPattern.conditioning) return BodySection.cardio;
    if (pattern == MovementPattern.mobility) return BodySection.mobility;

    return switch (primaryMuscles.firstOrNull) {
      'chest' => BodySection.chest,
      'lats' ||
      'traps' ||
      'rhomboids' ||
      'upperBack' ||
      'thoracicSpine' => BodySection.upperBack,
      'lowerBack' || 'spine' => BodySection.lowerBack,
      'frontDelts' ||
      'sideDelts' ||
      'rearDelts' ||
      'shoulders' ||
      'rotatorCuff' => BodySection.shoulders,
      'biceps' || 'triceps' || 'brachialis' || 'grip' => BodySection.arms,
      'core' || 'obliques' => BodySection.core,
      'glutes' => BodySection.glutes,
      'quads' ||
      'hamstrings' ||
      'calves' ||
      'adductors' ||
      'legs' ||
      'ankles' ||
      'hipFlexors' ||
      'hips' => BodySection.legs,
      _ => BodySection.fullBody,
    };
  }
}

/// How an exercise is loaded — decides which fields the logger shows, what a
/// stepper's increment is, and whether tonnage doubles for two hands.
enum LoadType {
  barbell,
  dumbbellPerHand,
  kettlebell,
  machine,
  cable,
  bodyweight,
  band,

  /// Held or worked for time — planks, carries, bike intervals.
  time,

  /// Covered distance — sled pushes, rows, runs.
  distance;

  /// Whether an e1RM is meaningful (ADR §4.4). Bodyweight, band, time and
  /// distance work has no external load to extrapolate from, so charting a
  /// one-rep max for it would be fiction.
  bool get isLoadable => switch (this) {
    LoadType.barbell ||
    LoadType.dumbbellPerHand ||
    LoadType.kettlebell ||
    LoadType.machine ||
    LoadType.cable => true,
    LoadType.bodyweight ||
    LoadType.band ||
    LoadType.time ||
    LoadType.distance => false,
  };

  /// Dumbbells are logged per hand, so session tonnage counts both
  /// (ADR §4.4).
  int get tonnageMultiplier => this == LoadType.dumbbellPerHand ? 2 : 1;

  /// Default weight-stepper increment in kg. Dumbbells and kettlebells come
  /// in coarser jumps than a barbell's smallest plate pair.
  double get defaultIncrementKg => switch (this) {
    LoadType.barbell => 2.5,
    LoadType.dumbbellPerHand => 1,
    LoadType.kettlebell => 2,
    LoadType.machine || LoadType.cable => 2.5,
    LoadType.bodyweight || LoadType.band => 1,
    LoadType.time || LoadType.distance => 1,
  };
}

/// A block within a session template (ADR §4.3 `block_templates.kind`).
enum BlockKind { warmup, main, core, conditioning, cooldown, plyo }

/// What a scheduled day is for (ADR §4.3 `scheduled_sessions.kind`).
enum ScheduledSessionKind {
  gym,
  rest,

  /// Cricket overrides gym as a first-class action, so a light week reads as
  /// intentional rather than as a gap (ADR §8.2).
  cricket,
  custom,
}

/// Where a scheduled day got to.
enum ScheduledSessionStatus {
  upcoming,
  inProgress,
  completed,

  /// Started and left unfinished — distinct from [skipped], which was never
  /// started.
  partial,
  skipped,
}

/// The outcome of a single prescribed set.
enum SetStatus { done, partial, skipped, substituted }

/// Which side a unilateral set was worked. [both] is the default: per-side
/// logging is more honest but roughly doubles the taps, so it is opt-in per
/// exercise (ADR §20.3 item 2).
enum SetSide { both, left, right }

/// Why a set was skipped. Reason capture is what makes Insights honest — a
/// skip with a reason is data, a silent gap is guilt (ADR §20.1 item 7).
enum SkipReason { pain, time, equipment, feltOff, other }

/// Input control a check-in metric renders as (ADR §4.3
/// `metric_definitions.input_type`).
enum MetricInputType { number, scale1to5, yesNo, photo }

/// Which record a `prs` row tracks (ADR §4.3).
enum PrMetric { e1RM, maxWeight, maxReps, maxVolume }

/// Local-only sync bookkeeping (ADR §4.2). Never sent to the server — it
/// describes this device's relationship to the row, not the row itself.
enum SyncState {
  synced,
  pendingCreate,
  pendingUpdate,
  pendingDelete,

  /// Push failed repeatedly or the server disagreed in a way the resolver
  /// would not settle silently. Surfaced in Settings rather than retried
  /// forever (ADR §6.2 rule 6).
  conflict;

  bool get isPending => this != SyncState.synced && this != SyncState.conflict;
}

/// The operation an outbox entry replays (ADR §4.3 `sync_outbox.op`).
enum OutboxOp { insert, update, delete }
