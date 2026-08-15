import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import '../app_database.dart';
import '../tables/plan_tables.dart';

part 'plan_dao.g.dart';

/// One program's worth of rows, before the mapper assembles them into a tree.
typedef PlanRows = ({
  ProgramRow program,
  List<PhaseRow> phases,
  List<SessionTemplateRow> sessions,
  List<BlockTemplateRow> blocks,
  List<ExerciseTemplateRow> exercises,
});

/// Reads and writes the template tree.
///
/// Two rules run through everything here:
///
/// 1. **Soft delete cascades by hand.** SQLite's `ON DELETE CASCADE` fires
///    only for real deletes, and this app never issues one (ADR §6.2 rule 5).
///    Hiding a phase therefore has to hide its sessions, blocks and exercise
///    slots in the same transaction — otherwise the next pull resurrects a
///    session whose blocks are gone.
/// 2. **Every mutation stamps `updated_at` and a pending sync state.** The
///    pull cursor and the outbox both key off them, so a write that skips
///    either is a row that silently never syncs.
@DriftAccessor(
  tables: [
    Programs,
    Phases,
    SessionTemplates,
    BlockTemplates,
    ExerciseTemplates,
  ],
)
class PlanDao extends DatabaseAccessor<AppDatabase> with _$PlanDaoMixin {
  PlanDao(super.attachedDatabase);

  // --- reads ---------------------------------------------------------------

  /// Headers only — a list screen doesn't need four whole trees to draw four
  /// rows.
  Stream<List<ProgramRow>> watchPrograms() {
    return (select(programs)
          ..where((row) => row.deletedAt.isNull())
          ..orderBy([
            (row) => OrderingTerm.desc(row.isActive),
            (row) => OrderingTerm.desc(row.startDate),
          ]))
        .watch();
  }

  Future<ProgramRow?> findProgram(String id) {
    return (select(programs)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<ProgramRow?> findActiveProgram() {
    return (select(programs)
          ..where((row) => row.isActive.equals(true) & row.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// Emits whenever anything in the active program's tree changes — including
  /// which program is active, and including a soft delete four levels down.
  Stream<PlanRows?> watchActivePlan() =>
      _watchPlanWhere(programs.isActive.equals(true));

  /// The whole tree for one program, as a live query.
  Stream<PlanRows?> watchPlan(String programId) =>
      _watchPlanWhere(programs.id.equals(programId));

  Future<PlanRows?> loadPlan(String programId) => watchPlan(programId).first;

  /// **One joined query, not four nested ones.**
  ///
  /// The obvious shape — watch phases, then sessions, then blocks — needs
  /// `switchMap` and tears down and rebuilds three subscriptions every time a
  /// single row changes, which in a builder screen is every keystroke. A left
  /// join reads the tree in one statement that drift invalidates correctly,
  /// and the row count stays small: it is the number of exercise slots in the
  /// program, around 200 for a ten-week block.
  ///
  /// The filters live in the join conditions rather than the `WHERE` clause on
  /// purpose. On a left join, `WHERE child.deleted_at IS NULL` would drop the
  /// parent row too, so a phase whose only session was deleted would vanish
  /// from the builder instead of showing up empty.
  Stream<PlanRows?> _watchPlanWhere(Expression<bool> programFilter) {
    final query =
        select(programs).join([
            leftOuterJoin(
              phases,
              phases.programId.equalsExp(programs.id) &
                  phases.deletedAt.isNull(),
            ),
            leftOuterJoin(
              sessionTemplates,
              sessionTemplates.phaseId.equalsExp(phases.id) &
                  sessionTemplates.deletedAt.isNull(),
            ),
            leftOuterJoin(
              blockTemplates,
              blockTemplates.sessionTemplateId.equalsExp(sessionTemplates.id) &
                  blockTemplates.deletedAt.isNull(),
            ),
            leftOuterJoin(
              exerciseTemplates,
              exerciseTemplates.blockTemplateId.equalsExp(blockTemplates.id) &
                  exerciseTemplates.deletedAt.isNull(),
            ),
          ])
          ..where(programFilter & programs.deletedAt.isNull())
          ..orderBy([
            OrderingTerm(expression: phases.orderIndex),
            OrderingTerm(expression: sessionTemplates.orderIndex),
            OrderingTerm(expression: blockTemplates.orderIndex),
            OrderingTerm(expression: exerciseTemplates.orderIndex),
          ]);

    return query.watch().map(_collect);
  }

  /// Flattens the join back into one row per entity, preserving the query's
  /// order. A left join repeats every ancestor once per descendant, so
  /// deduplication is not an optimisation — without it a phase with twelve
  /// exercise slots would appear twelve times.
  PlanRows? _collect(List<TypedResult> rows) {
    if (rows.isEmpty) return null;

    final phaseRows = <String, PhaseRow>{};
    final sessionRows = <String, SessionTemplateRow>{};
    final blockRows = <String, BlockTemplateRow>{};
    final exerciseRows = <String, ExerciseTemplateRow>{};

    for (final row in rows) {
      if (row.readTableOrNull(phases) case final phase?) {
        phaseRows[phase.id] = phase;
      }
      if (row.readTableOrNull(sessionTemplates) case final session?) {
        sessionRows[session.id] = session;
      }
      if (row.readTableOrNull(blockTemplates) case final block?) {
        blockRows[block.id] = block;
      }
      if (row.readTableOrNull(exerciseTemplates) case final exercise?) {
        exerciseRows[exercise.id] = exercise;
      }
    }

    return (
      program: rows.first.readTable(programs),
      phases: phaseRows.values.toList(),
      sessions: sessionRows.values.toList(),
      blocks: blockRows.values.toList(),
      exercises: exerciseRows.values.toList(),
    );
  }

  // --- program -------------------------------------------------------------

  Future<ProgramRow> createProgram({
    required String name,
    required String startDate,
    String? notes,
  }) {
    return into(programs).insertReturning(
      ProgramsCompanion.insert(
        name: name,
        startDate: startDate,
        notes: Value(notes),
      ),
    );
  }

  /// Deliberately does **not** touch `schedule_pattern`: renaming a program
  /// must not silently discard its calendar. Committing a schedule is the only
  /// thing that writes that column.
  Future<void> updateProgram({
    required String id,
    required String name,
    required String startDate,
    String? endDate,
    String? notes,
  }) async {
    await (update(programs)..where((row) => row.id.equals(id))).write(
      ProgramsCompanion(
        name: Value(name),
        startDate: Value(startDate),
        endDate: Value(endDate),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
        syncState: const Value(SyncState.pendingUpdate),
      ),
    );
  }

  /// Activating one program deactivates the rest, in one transaction — two
  /// active programs would make "today's session" ambiguous.
  Future<void> setActiveProgram(String id) async {
    await transaction(() async {
      final now = DateTime.now();

      await (update(programs)..where(
            (row) => row.isActive.equals(true) & row.id.equals(id).not(),
          ))
          .write(
            ProgramsCompanion(
              isActive: const Value(false),
              updatedAt: Value(now),
              syncState: const Value(SyncState.pendingUpdate),
            ),
          );

      await (update(programs)..where((row) => row.id.equals(id))).write(
        ProgramsCompanion(
          isActive: const Value(true),
          updatedAt: Value(now),
          syncState: const Value(SyncState.pendingUpdate),
        ),
      );
    });
  }

  /// Hides a program and everything under it.
  Future<void> deleteProgram(String id) async {
    await transaction(() async {
      final phaseIds = await _idsOf(
        select(phases)..where((row) => row.programId.equals(id)),
        (row) => row.id,
      );

      await _softDelete(programs, [id]);
      await _deletePhases(phaseIds);
    });
  }

  // --- phase ---------------------------------------------------------------

  Future<PhaseRow> createPhase({
    required String programId,
    required String name,
    required int startWeek,
    required int endWeek,
  }) async {
    final orderIndex = await _nextOrderIndex(
      select(phases)..where((row) => row.programId.equals(programId)),
      (row) => row.orderIndex,
    );

    return into(phases).insertReturning(
      PhasesCompanion.insert(
        programId: programId,
        name: name,
        orderIndex: orderIndex,
        startWeek: startWeek,
        endWeek: endWeek,
      ),
    );
  }

  Future<void> updatePhase(PhasesCompanion phase, String id) async {
    await (update(phases)..where((row) => row.id.equals(id))).write(
      phase.copyWith(
        updatedAt: Value(DateTime.now()),
        syncState: const Value(SyncState.pendingUpdate),
      ),
    );
  }

  Future<void> deletePhase(String id) => transaction(() => _deletePhases([id]));

  // --- session -------------------------------------------------------------

  Future<SessionTemplateRow> createSession({
    required String phaseId,
    required String code,
    required String title,
    int? dayOfWeek,
  }) async {
    final orderIndex = await _nextOrderIndex(
      select(sessionTemplates)..where((row) => row.phaseId.equals(phaseId)),
      (row) => row.orderIndex,
    );

    return into(sessionTemplates).insertReturning(
      SessionTemplatesCompanion.insert(
        phaseId: phaseId,
        code: code,
        title: title,
        dayOfWeek: Value(dayOfWeek),
        orderIndex: orderIndex,
      ),
    );
  }

  Future<void> updateSession(
    SessionTemplatesCompanion session,
    String id,
  ) async {
    await (update(sessionTemplates)..where((row) => row.id.equals(id))).write(
      session.copyWith(
        updatedAt: Value(DateTime.now()),
        syncState: const Value(SyncState.pendingUpdate),
      ),
    );
  }

  Future<void> deleteSession(String id) =>
      transaction(() => _deleteSessions([id]));

  // --- block ---------------------------------------------------------------

  Future<BlockTemplateRow> createBlock({
    required String sessionTemplateId,
    required BlockKind kind,
    required String title,
  }) async {
    final orderIndex = await _nextOrderIndex(
      select(blockTemplates)
        ..where((row) => row.sessionTemplateId.equals(sessionTemplateId)),
      (row) => row.orderIndex,
    );

    return into(blockTemplates).insertReturning(
      BlockTemplatesCompanion.insert(
        sessionTemplateId: sessionTemplateId,
        kind: kind,
        title: title,
        orderIndex: orderIndex,
      ),
    );
  }

  Future<void> updateBlock(BlockTemplatesCompanion block, String id) async {
    await (update(blockTemplates)..where((row) => row.id.equals(id))).write(
      block.copyWith(
        updatedAt: Value(DateTime.now()),
        syncState: const Value(SyncState.pendingUpdate),
      ),
    );
  }

  Future<void> deleteBlock(String id) => transaction(() => _deleteBlocks([id]));

  // --- exercise slot -------------------------------------------------------

  Future<ExerciseTemplateRow> createExercise(
    ExerciseTemplatesCompanion exercise,
  ) async {
    final orderIndex = await _nextOrderIndex(
      select(exerciseTemplates)..where(
        (row) => row.blockTemplateId.equals(exercise.blockTemplateId.value),
      ),
      (row) => row.orderIndex,
    );

    return into(
      exerciseTemplates,
    ).insertReturning(exercise.copyWith(orderIndex: Value(orderIndex)));
  }

  Future<void> updateExercise(
    ExerciseTemplatesCompanion exercise,
    String id,
  ) async {
    await (update(exerciseTemplates)..where((row) => row.id.equals(id))).write(
      exercise.copyWith(
        updatedAt: Value(DateTime.now()),
        syncState: const Value(SyncState.pendingUpdate),
      ),
    );
  }

  Future<void> deleteExercise(String id) async {
    await _softDelete(exerciseTemplates, [id]);
  }

  // --- reordering ----------------------------------------------------------

  /// Rewrites `order_index` from the given order, in one transaction. Taking
  /// the whole sibling list rather than a from/to pair means a drag that
  /// raced another edit can't leave two rows claiming the same slot.
  Future<void> reorderPhases(List<String> orderedIds) => _reorder(
    phases,
    orderedIds,
    (index) => PhasesCompanion(orderIndex: Value(index)),
  );

  Future<void> reorderSessions(List<String> orderedIds) => _reorder(
    sessionTemplates,
    orderedIds,
    (index) => SessionTemplatesCompanion(orderIndex: Value(index)),
  );

  Future<void> reorderBlocks(List<String> orderedIds) => _reorder(
    blockTemplates,
    orderedIds,
    (index) => BlockTemplatesCompanion(orderIndex: Value(index)),
  );

  Future<void> reorderExercises(List<String> orderedIds) => _reorder(
    exerciseTemplates,
    orderedIds,
    (index) => ExerciseTemplatesCompanion(orderIndex: Value(index)),
  );

  // --- internals -----------------------------------------------------------

  Future<void> _deletePhases(List<String> ids) async {
    if (ids.isEmpty) return;

    final sessionIds = await _idsOf(
      select(sessionTemplates)..where((row) => row.phaseId.isIn(ids)),
      (row) => row.id,
    );

    await _softDelete(phases, ids);
    await _deleteSessions(sessionIds);
  }

  Future<void> _deleteSessions(List<String> ids) async {
    if (ids.isEmpty) return;

    final blockIds = await _idsOf(
      select(blockTemplates)..where((row) => row.sessionTemplateId.isIn(ids)),
      (row) => row.id,
    );

    await _softDelete(sessionTemplates, ids);
    await _deleteBlocks(blockIds);
  }

  Future<void> _deleteBlocks(List<String> ids) async {
    if (ids.isEmpty) return;

    final exerciseIds = await _idsOf(
      select(exerciseTemplates)..where((row) => row.blockTemplateId.isIn(ids)),
      (row) => row.id,
    );

    await _softDelete(blockTemplates, ids);
    await _softDelete(exerciseTemplates, exerciseIds);
  }

  /// Marks rows deleted and pending, in one statement per table.
  Future<void> _softDelete<T extends Table, R>(
    TableInfo<T, R> table,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return;

    final now = DateTime.now();
    await customUpdate(
      'UPDATE ${table.actualTableName} '
      'SET deleted_at = ?, updated_at = ?, sync_state = ? '
      'WHERE id IN (${List.filled(ids.length, '?').join(', ')}) '
      'AND deleted_at IS NULL',
      variables: [
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(SyncState.pendingDelete.name),
        ...ids.map(Variable<String>.new),
      ],
      updates: {table},
    );
  }

  Future<void> _reorder<T extends Table, R>(
    TableInfo<T, R> table,
    List<String> orderedIds,
    Insertable<R> Function(int index) companionFor,
  ) async {
    if (orderedIds.isEmpty) return;

    await transaction(() async {
      final now = DateTime.now();
      for (var index = 0; index < orderedIds.length; index++) {
        await (update(table)
              ..where((row) => (row as dynamic).id.equals(orderedIds[index])))
            .write(companionFor(index));
      }

      // One timestamp bump for the whole reorder rather than per row: the sync
      // layer only needs to know the rows changed.
      await customUpdate(
        'UPDATE ${table.actualTableName} '
        'SET updated_at = ?, sync_state = ? '
        'WHERE id IN (${List.filled(orderedIds.length, '?').join(', ')})',
        variables: [
          Variable<DateTime>(now),
          Variable<String>(SyncState.pendingUpdate.name),
          ...orderedIds.map(Variable<String>.new),
        ],
        updates: {table},
      );
    });
  }

  Future<List<String>> _idsOf<T extends HasResultSet, R>(
    SimpleSelectStatement<T, R> query,
    String Function(R row) id,
  ) async {
    final rows = await query.get();
    return rows.map(id).toList();
  }

  /// Next free slot at the end of a sibling list.
  ///
  /// Counts **soft-deleted siblings too**, and reads the maximum rather than
  /// the row count. A hidden row is not gone — an undo, or a pull from a
  /// device that still has it, brings it back — and reusing its index would
  /// leave two siblings claiming the same position, which orders
  /// nondeterministically.
  Future<int> _nextOrderIndex<T extends HasResultSet, R>(
    SimpleSelectStatement<T, R> query,
    int Function(R row) orderIndex,
  ) async {
    final rows = await query.get();
    if (rows.isEmpty) return 0;
    return rows.map(orderIndex).reduce((a, b) => a > b ? a : b) + 1;
  }
}
