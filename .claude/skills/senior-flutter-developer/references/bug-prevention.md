# Bug Prevention, Memory & Correctness

Depth reference for shipping Flutter that doesn't crash, leak, or jank. Read before writing
non-trivial logic.

## The disposal discipline (memory leaks)

A leak in Flutter is almost always **something created in `initState`/a provider/a bloc that was
never disposed**. Make disposal a build-time reflex, paired 1:1 with creation.

Dispose/cancel in `State.dispose()` (or provider `ref.onDispose` / bloc `close`):

| Created | Cleanup |
|---|---|
| `AnimationController`, `TabController`, `PageController`, `ScrollController` | `.dispose()` |
| `TextEditingController`, `FocusNode` | `.dispose()` |
| `StreamSubscription` (`.listen`) | `.cancel()` |
| `StreamController`, RxDart `Subject` | `.close()` |
| `Timer`, `Ticker` | `.cancel()` / `.dispose()` |
| `addListener(...)` | matching `removeListener(...)` |
| `OverlayEntry` | `.remove()` |

Rules:
- `dispose()` ends with `super.dispose()`; never touch a controller after disposing it.
- Scoped Riverpod providers: rely on `autoDispose` + `ref.onDispose` for anything you allocate.
- BLoC/Cubit: cancel internal subscriptions in `close()` then `return super.close()`; let
  `BlocProvider` own the bloc lifecycle when possible.
- Don't hold `BuildContext`, `State`, or large objects in long-lived singletons/static fields — a
  classic leak that also causes "used after dispose" crashes.

## Async safety in widgets

- After every `await` in a `State` method, **`if (!mounted) return;`** before `setState`/`context`.
- Don't capture `context` across an async gap and use it later without re-checking `mounted`
  (`Navigator`, `ScaffoldMessenger`, `Theme.of`).
- Cancel in-flight work on dispose (cancel the subscription, ignore late futures via the `mounted`
  guard, or use a cancellation token for repositories).

```dart
Future<void> _save() async {
  final messenger = ScaffoldMessenger.of(context); // capture BEFORE await if you must use it after
  await repo.save(_form);
  if (!mounted) return;
  messenger.showSnackBar(const SnackBar(content: Text('Saved')));
}
```

## Null safety & exhaustiveness

- Avoid `!` and `as` where they can fail; use `?.`, `??`, `if (x case Foo f)`, pattern matching.
- Model variants with **sealed classes / enums** and `switch` *expressions* so the compiler forces
  you to handle every case — no silent `default` that swallows a new variant later.
- Decode defensively: `Map`/`List` access from JSON can be null or the wrong type; validate at the
  boundary, don't bang through it.

```dart
final state = switch (status) {
  Status.loading => const Spinner(),
  Status.ready   => Content(data!),   // only reachable when non-null by construction
  Status.failed  => const ErrorView(),
};
```

## Common Flutter crash/bug sources (and the fix)

- **`setState() called after dispose`** → guard with `mounted`; cancel async work on dispose.
- **`setState() during build`** → don't mutate state synchronously in `build`; defer with
  `WidgetsBinding.instance.addPostFrameCallback`.
- **Unbounded height/width errors** (`RenderFlex overflowed`, "viewport unbounded") → give lists/
  columns bounded constraints (`Expanded`, `Flexible`, `SizedBox`, `shrinkWrap` only when small).
- **`A RenderObject was assigned to multiple parents` / duplicate `GlobalKey`** → don't reuse a
  `GlobalKey` across widgets; use `ValueKey`/`ObjectKey` for list identity.
- **Stale closures over old state** → in callbacks read the latest source of truth, don't capture a
  snapshot from `build`.
- **Dropped errors** → no empty `catch {}`; either handle or rethrow with context.
- **Listener leaks** → every `addListener` has a `removeListener`.

## Rebuild correctness & performance

- `const` constructors everywhere possible — they let Flutter skip rebuilding subtrees.
- Split big widgets so a small state change doesn't rebuild a large tree; push state down to the
  smallest widget that needs it.
- Long/again-scrolling lists: `ListView.builder` / slivers with stable keys, not a `Column` of N
  children. `RepaintBoundary` around expensive, independently-updating subtrees.
- Keep heavy computation out of `build()` (memoize, precompute, or move to an isolate via
  `compute`/`Isolate.run` for CPU-bound work).
- Use `Builder`/`Consumer`/`select`/`buildWhen` to scope rebuilds to what actually changed.

## Testing (prove it works)

- **Unit**: pure logic, repositories, mappers. Inject fakes via constructors.
- **Provider/bloc**: `ProviderContainer` with overrides (dispose it in teardown) / `bloc_test`.
- **Widget**: `testWidgets` + `pumpWidget`; `pump`/`pumpAndSettle` to advance animations; find by
  key/semantics; assert on states (loading → data → error). Use `tester.pumpAndSettle()` to flush
  animations and `mockNetworkImagesFor`-style fakes for images.
- **Golden** tests for critical UI where pixel regressions matter.

```dart
testWidgets('shows error then retries', (tester) async {
  await tester.pumpWidget(wrap(const TodoScreen()));
  await tester.pumpAndSettle();
  expect(find.byType(ErrorView), findsOneWidget);
  await tester.tap(find.text('Retry'));
  await tester.pumpAndSettle();
  expect(find.byType(TodoListView), findsOneWidget);
});
```

## Final gate before delivering

If you can't tick these, fix before handing over: **nothing undisposed, no unguarded async
`context`, no failing `!`/`as`, exhaustive state handling, no swallowed errors, lists virtualized,
`const` where possible, and at least the critical path is testable.**
