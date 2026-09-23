import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design/tokens.dart';
import '../features/editor/editor_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/library_shell.dart';
import '../features/library/sessions_screen.dart';
import '../features/settings/settings_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: Motion.snappy,
  reverseTransitionDuration: Motion.quick,
  transitionsBuilder: (context, animation, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Motion.glideEnter),
    child: child,
  ),
);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      ShellRoute(
        pageBuilder: (context, state, child) => _fade(state, LibraryShell(child: child)),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (c, s) => NoTransitionPage(child: const HomeScreen()),
          ),
          GoRoute(
            path: '/scripts',
            pageBuilder: (c, s) => const NoTransitionPage(child: ScriptListScreen(filter: LibraryFilter.all())),
          ),
          GoRoute(
            path: '/archive',
            pageBuilder: (c, s) => const NoTransitionPage(child: ScriptListScreen(filter: LibraryFilter.archive())),
          ),
          GoRoute(
            path: '/collections/:id',
            pageBuilder: (c, s) =>
                NoTransitionPage(child: ScriptListScreen(filter: LibraryFilter.collection(s.pathParameters['id']!))),
          ),
          GoRoute(
            path: '/sessions',
            pageBuilder: (c, s) => const NoTransitionPage(child: SessionsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/script/:id',
        pageBuilder: (c, s) => _fade(
          s,
          EditorScreen(
            scriptId: s.pathParameters['id']!,
            tab: EditorTab.values.asNameMap()[s.uri.queryParameters['tab']] ?? EditorTab.write,
          ),
        ),
      ),
      GoRoute(path: '/settings', redirect: (c, s) => '/settings/shortcuts'),
      GoRoute(
        path: '/settings/:page',
        pageBuilder: (c, s) => _fade(
          s,
          SettingsScreen(page: SettingsPage.values.asNameMap()[s.pathParameters['page']] ?? SettingsPage.shortcuts),
        ),
      ),
    ],
  );
});
