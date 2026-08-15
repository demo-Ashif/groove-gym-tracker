# State Management: Riverpod & BLoC/Cubit

Depth reference for writing idiomatic, leak-free state. Pick the tool the codebase/user wants; the
correctness rules below apply to both.

## Choosing between them

| Want | Lean |
|---|---|
| Fine-grained reactive providers, easy derived/async state, no `BuildContext` for reads, compile-safe | **Riverpod** |
| Explicit event→state contract, traceable transitions, team already on BLoC | **BLoC** |
| Simple imperative state without events | **Cubit** (BLoC family) |

Both are testable and production-grade. Don't mix paradigms inside one feature without reason.

---

## Riverpod (v2+)

Prefer the **generator** (`riverpod_generator` + `riverpod_annotation`) — it's the current idiom and
removes a class of provider-type mistakes. Plain providers are fine when codegen isn't wanted.

### Synchronous state — Notifier

```dart
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0; // initial state

  void increment() => state++;
}
// read:    final count = ref.watch(counterProvider);
// mutate:  ref.read(counterProvider.notifier).increment();
```

### Async state — AsyncNotifier (loading/data/error for free)

```dart
@riverpod
class TodoList extends _$TodoList {
  @override
  Future<List<Todo>> build() async {
    final repo = ref.watch(todoRepoProvider);
    return repo.fetchAll();
  }

  Future<void> add(Todo t) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(todoRepoProvider).add(t);
      return ref.read(todoRepoProvider).fetchAll();
    });
  }
}
```

Render `AsyncValue` exhaustively — never just the data path:

```dart
final todos = ref.watch(todoListProvider);
return todos.when(
  data: (list) => TodoListView(list),
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (e, st) => ErrorView(e, onRetry: () => ref.invalidate(todoListProvider)),
);
```

### Lifecycle & leaks — the important part

- **`autoDispose` by default for screen-scoped state.** With codegen, providers are autoDispose
  unless you mark `@Riverpod(keepAlive: true)`. A non-disposed provider holding a subscription or
  controller is a leak.
- Use **`ref.onDispose`** to clean up anything you create inside a provider (close a controller,
  cancel a subscription, kill a timer).
- Use **`ref.keepAlive()`** deliberately when you want to cache past the last listener (then often a
  `Timer` + `link.close()` to expire it).
- **`ref.listen`** for side effects (navigation, snackbars) — never trigger side effects from
  `build`.

```dart
@riverpod
Stream<int> ticks(TicksRef ref) {
  final controller = StreamController<int>();
  final timer = Timer.periodic(const Duration(seconds: 1), (t) => controller.add(t.tick));
  ref.onDispose(() {            // <- prevents the leak
    timer.cancel();
    controller.close();
  });
  return controller.stream;
}
```

### Performance

- **`ref.watch(provider.select((s) => s.field))`** to rebuild only when one field changes.
- Watch the *narrowest* provider a widget needs; split big state objects into focused providers.
- `family` for parameterized providers; combine `family` + `autoDispose` for per-argument scoped state.
- Reads vs watches: `watch` in `build`, `read` in callbacks, `listen` for effects. Never `read` in
  `build` to dodge rebuilds — that's a stale-state bug.

### Testing

```dart
final container = ProviderContainer(overrides: [
  todoRepoProvider.overrideWithValue(FakeRepo()),
]);
addTearDown(container.dispose); // dispose the container in tests too
```

---

## BLoC / Cubit (`flutter_bloc`)

### Cubit — simple imperative state

```dart
class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);
  void increment() => emit(state + 1);
}
```

### BLoC — event-driven, with a modelled state

Model state as a **sealed union**, not loose flags, so the UI handles every case. Per house style
prefer a **freezed** union for real features (see `references/architecture-and-navigation.md`); a
hand-written sealed class like below is fine for small/snippet cases:

```dart
sealed class TodoState {}
class TodoLoading extends TodoState {}
class TodoLoaded extends TodoState { TodoLoaded(this.todos); final List<Todo> todos; }
class TodoError extends TodoState { TodoError(this.message); final String message; }

class TodoBloc extends Bloc<TodoEvent, TodoState> {
  TodoBloc(this._repo) : super(TodoLoading()) {
    on<TodoRequested>(_onRequested);
    on<TodoAdded>(_onAdded, transformer: droppable()); // bloc_concurrency for event flow control
  }
  final TodoRepo _repo;

  Future<void> _onRequested(TodoRequested e, Emitter<TodoState> emit) async {
    emit(TodoLoading());
    try {
      emit(TodoLoaded(await _repo.fetchAll()));
    } catch (err) {
      emit(TodoError(err.toString()));
    }
  }
}
```

Use **`bloc_concurrency`** transformers (`sequential`, `droppable`, `restartable`, `concurrent`)
deliberately — e.g. `restartable()` for search-as-you-type so stale requests are cancelled.

### Consuming in the UI

- `BlocBuilder` to rebuild on state, `BlocListener` for one-off effects (nav/snackbar),
  `BlocConsumer` for both, `context.select<Bloc, T>(...)` / `buildWhen` to limit rebuilds.

```dart
BlocBuilder<TodoBloc, TodoState>(
  builder: (context, state) => switch (state) {
    TodoLoading() => const Center(child: CircularProgressIndicator()),
    TodoLoaded(:final todos) => TodoListView(todos),
    TodoError(:final message) => ErrorView(message),
  },
);
```

### Lifecycle & leaks

- A BLoC/Cubit owns subscriptions — **cancel them in `close()`** and call `super.close()`:

```dart
@override
Future<void> close() {
  _sub.cancel();
  return super.close();
}
```

- Prefer `BlocProvider` to own a bloc's lifecycle (it calls `close()` for you). Only create a bloc
  manually if you also dispose it manually.
- Don't `emit` after `close()` (guard with `isClosed` or, inside handlers, check `emit.isDone`).
- For long-lived streams inside a bloc, use `emit.forEach`/`emit.onEach` so cancellation is handled.

### Testing

Use `bloc_test`:

```dart
blocTest<CounterCubit, int>(
  'emits [1] when increment is called',
  build: CounterCubit.new,
  act: (c) => c.increment(),
  expect: () => [1],
);
```

---

## Shared rules (both)

- Keep **all** business logic out of `build()` and out of widgets.
- Model async as explicit **loading / data / error** states.
- Expose immutable state; never mutate in place — emit/return new values. Use **freezed** for state
  classes/unions (`copyWith` + equality + exhaustive matching); use **equatable** for plain
  domain/value objects where you're not codegen-ing. Don't stack both on one class.
- One source of truth per piece of state; derive the rest.
