import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/chat/chat_screen.dart';
import '../features/forms/forms_screen.dart';
import '../features/editor/editor_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/library_shell.dart';
import '../features/library/sessions_screen.dart';
import '../features/settings/settings_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// A quick fade between pages: the new one is there within 150 ms and the
/// old one leaves at once, so switching sections never feels like waiting.
/// Instant under reduced motion.
Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 150),
  reverseTransitionDuration: Duration.zero,
  transitionsBuilder: (context, animation, _, child) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    );
  },
);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      ShellRoute(
        pageBuilder: (context, state, child) => _fade(state, LibraryShell(child: child)),
        routes: [
          GoRoute(path: '/', pageBuilder: (c, s) => _fade(s, const HomeScreen())),
          GoRoute(
            path: '/scripts',
            pageBuilder: (c, s) => _fade(s, const ScriptListScreen(filter: LibraryFilter.all())),
          ),
          GoRoute(
            path: '/archive',
            pageBuilder: (c, s) => _fade(s, const ScriptListScreen(filter: LibraryFilter.archive())),
          ),
          GoRoute(
            path: '/collections/:id',
            pageBuilder: (c, s) =>
                _fade(s, ScriptListScreen(filter: LibraryFilter.collection(s.pathParameters['id']!))),
          ),
          GoRoute(path: '/sessions', pageBuilder: (c, s) => _fade(s, const SessionsScreen())),
          GoRoute(path: '/chat', pageBuilder: (c, s) => _fade(s, const ChatScreen())),
          GoRoute(path: '/forms', pageBuilder: (c, s) => _fade(s, const FormsScreen())),
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
