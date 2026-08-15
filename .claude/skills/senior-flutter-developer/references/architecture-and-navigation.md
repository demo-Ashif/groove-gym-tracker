# Architecture & Navigation

Depth reference for the layered structure, where codegen belongs, and go_router. This is the house
style — match an existing codebase's conventions if they differ.

## Layering

```
lib/
├─ core/                      # cross-cutting: theme, errors, extensions, DI wiring
└─ features/<feature>/
   ├─ presentation/          # widgets, screens, controllers/blocs, freezed UI state
   ├─ domain/                # PURE: entities, value objects, repository INTERFACES, usecases
   └─ data/                  # DTOs (json_serializable), datasources, repository IMPLEMENTATIONS
```

Dependency rule: **presentation → domain ← data.** Domain depends on nothing Flutter- or
serialization-specific. Data implements domain interfaces and maps DTO → entity.

## Where codegen belongs

| Concern | Tool | Layer | Notes |
|---|---|---|---|
| State classes / unions | **freezed** | presentation (and complex notifier/bloc state) | `copyWith`, unions, equality. Not for every model. |
| JSON parsing | **json_serializable / json_annotation** | **data only** | DTOs carry `fromJson`/`toJson`. |
| Value equality (no freezed) | **equatable** | domain (entities/value objects), simple states | Don't combine with freezed. |
| Providers | riverpod_generator | presentation/data wiring | optional but preferred. |

### Domain entity (pure — no JSON, equality via Equatable)

```dart
// domain/entities/user.dart
import 'package:equatable/equatable.dart';

class User extends Equatable {
  const User({required this.id, required this.name, required this.email});
  final String id;
  final String name;
  final String email;
  @override
  List<Object?> get props => [id, name, email];
}
```

### Data DTO (json_serializable) + mapping to the entity

```dart
// data/models/user_dto.dart
import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/user.dart';
part 'user_dto.g.dart';

@JsonSerializable()
class UserDto {
  const UserDto({required this.id, required this.name, required this.email});
  factory UserDto.fromJson(Map<String, dynamic> json) => _$UserDtoFromJson(json);
  final String id;
  final String name;
  final String email;
  Map<String, dynamic> toJson() => _$UserDtoToJson(this);

  User toEntity() => User(id: id, name: name, email: email); // DTO -> pure entity
}
```

The repository implementation returns **entities**, never DTOs — JSON never escapes the data layer.

### State class (freezed union)

```dart
// presentation/profile/profile_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/entities/user.dart';
part 'profile_state.freezed.dart';

@freezed
sealed class ProfileState with _$ProfileState {
  const factory ProfileState.loading() = ProfileLoading;
  const factory ProfileState.loaded(User user) = ProfileLoaded;
  const factory ProfileState.error(String message) = ProfileError;
}
```

Consume with an exhaustive `switch` (the compiler enforces all cases):

```dart
switch (state) {
  ProfileLoading() => const Spinner(),
  ProfileLoaded(:final user) => ProfileView(user),
  ProfileError(:final message) => ErrorView(message),
}
```

**Run codegen** after touching any annotated file:
```
dart run build_runner build --delete-conflicting-outputs
```

## Navigation — go_router

Use `go_router` for declarative, URL-driven navigation with deep-link support. Centralize the
router; don't scatter raw path strings through widgets.

```dart
// core/router/app_router.dart
final goRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider); // listenable below if it changes
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,          // re-evaluate redirect when auth changes
    redirect: (context, state) {
      final loggedIn = auth.isLoggedIn;
      final loggingIn = state.matchedLocation == '/login';
      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(                       // persistent shell (e.g. bottom nav)
        builder: (_, __, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const FeedScreen(),
            routes: [
              GoRoute(
                path: 'item/:id',       // /item/123
                builder: (_, state) =>
                    ItemScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        ],
      ),
    ],
    errorBuilder: (_, state) => NotFoundScreen(uri: state.uri),
  );
});
```

Wire it with `MaterialApp.router(routerConfig: ref.watch(goRouterProvider))`.

Guidelines:
- Navigate with `context.go('/path')` (replace stack) vs `context.push('/path')` (push on top).
- Read params via `state.pathParameters` / `state.uri.queryParameters`; pass complex objects via
  `extra` only for non-deep-linkable data.
- Centralize path constants or use **type-safe routes** (`go_router_builder`) for larger apps so
  paths aren't stringly-typed.
- Put auth/role gating in `redirect` with `refreshListenable`, not scattered `if` checks in widgets.
- `ShellRoute` / `StatefulShellRoute.indexedStack` for bottom-nav apps that keep tab state.
