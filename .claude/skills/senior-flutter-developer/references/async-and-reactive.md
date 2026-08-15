# Async, Streams & RxDart

Depth reference for asynchronous Dart and reactive composition. The recurring theme: **every stream
you listen to or create must be disposed**, and **errors must have a home**.

## Futures & async correctness

- `await` futures, or fire-and-forget *intentionally* with error handling — never leave a future
  dangling such that a thrown error vanishes (`unawaited(...)` from `dart:async` documents intent).
- Wrap fallible awaits in `try/catch`; convert to typed results/`AsyncValue` at the boundary rather
  than letting raw exceptions reach the UI.
- After any `await` in a `State`, **check `mounted`** before touching `context`/`setState`. In a
  provider/bloc, the framework guards this, but in widget code it's on you.
- `Future.wait` to parallelize independent work; sequence only when there's a real dependency.
- Use `Completer` only when bridging callback APIs — prefer `async`/`await` otherwise.

```dart
Future<void> _load() async {
  try {
    final data = await repo.fetch();
    if (!mounted) return;        // guard before setState/context
    setState(() => _data = data);
  } on SocketException {
    if (mounted) setState(() => _error = 'No connection');
  }
}
```

## Streams — the basics done right

- **Single-subscription** stream: exactly one listener over its lifetime (default `StreamController`).
  **Broadcast**: many listeners (`StreamController.broadcast()`), but listeners that subscribe late
  miss earlier events.
- A `StreamSubscription` from `.listen(...)` **must be cancelled** — store it and cancel in
  `dispose()`/`close()`. This is the #1 Flutter stream leak.
- A `StreamController` you create **must be closed**.
- Provide `onError` (and `cancelOnError` consciously) wherever the stream can fail.

```dart
class _LiveState extends State<Live> {
  StreamSubscription<Quote>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = quotes().listen(
      (q) { if (mounted) setState(() => _quote = q); },
      onError: (e, st) { /* surface error */ },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();            // <- cancel, always
    super.dispose();
  }
}
```

- Prefer `StreamBuilder` for simple stream→widget cases; it manages the subscription for you. Still
  handle `snapshot.connectionState` and `snapshot.hasError`, not just `hasData`.
- `await for` consumes a stream in an async function; the loop ends on done — use it when you want
  sequential processing and natural cancellation via breaking the loop.
- Transform with `map`/`where`/`asyncMap`/`expand`; **`asyncMap`** preserves order for async work
  (vs firing concurrently).

## RxDart — when and how

Reach for RxDart when you need **subjects** (a stream you can also push into and read the latest
from) or **richer operators** than vanilla Dart streams provide. Don't add it just to write `.map`.

### Subjects (all are broadcast; all must be `.close()`d)

- **`BehaviorSubject<T>`** — caches the latest value and replays it to new listeners. The workhorse
  for "current state as a stream" (form fields, current user, selected tab). Read synchronously via
  `.value`.
- **`PublishSubject<T>`** — no replay; events only reach listeners subscribed at emit time. Good for
  one-shot events (button taps, navigation intents).
- **`ReplaySubject<T>`** — replays the last *N* (or all) events. Use sparingly; can hold memory.

```dart
final _query = BehaviorSubject<String>.seeded('');

Stream<List<Result>> get results => _query
    .debounceTime(const Duration(milliseconds: 300))
    .distinct()
    .switchMap((q) => Stream.fromFuture(repo.search(q))); // cancels stale searches

void dispose() => _query.close(); // close every subject
```

### Operators worth knowing

- **`debounceTime` / `throttleTime`** — tame chatty inputs (search, scroll).
- **`distinct`** — drop consecutive duplicates.
- **`switchMap`** — map to an inner stream and **cancel the previous inner** when a new outer event
  arrives. This is the correct operator for search-as-you-type and "latest wins" requests.
- **`flatMap`** — keep all inner streams alive (concurrent); use when every result matters.
- **`combineLatest2/3/…`** — combine the latest of several streams (e.g. form validity from multiple
  fields).
- **`startWith` / `scan`** — seed an initial value / accumulate state over events.
- **`withLatestFrom`** — sample another stream's latest on each event.

### combineLatest example (reactive form validity)

```dart
Stream<bool> get formValid => Rx.combineLatest2(
  _email.stream.map(_isEmail),
  _password.stream.map((p) => p.length >= 8),
  (bool e, bool p) => e && p,
);
```

## Backpressure & ordering

- Fast producer + slow consumer: buffer (`bufferTime`/`bufferCount`), sample (`sampleTime`), or drop
  (`throttle`) deliberately — don't let an unbounded buffer grow.
- `asyncMap` for ordered async transforms; `switchMap` when only the latest matters; `flatMap`/
  `concurrent` when all must complete.

## Disposal checklist for any stream-using class

- [ ] Every `.listen` result is stored and **cancelled**.
- [ ] Every `StreamController`/RxDart `Subject` you own is **closed**.
- [ ] No `emit`/`add` after close (`if (!subject.isClosed)` when in doubt).
- [ ] Broadcast vs single-subscription chosen on purpose.
- [ ] `onError` present wherever failure is possible; errors surfaced to the user, not swallowed.
- [ ] For per-screen streams, ownership lives in a provider (`ref.onDispose`) or bloc (`close`) or
      `State.dispose`, never floating globally.
