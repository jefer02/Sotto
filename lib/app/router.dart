import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/stage_transitions.dart';
import '../features/chat/chat_screen.dart';
import '../features/forms/forms_screen.dart';
import '../features/editor/editor_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/library_shell.dart';
import '../features/library/sessions_screen.dart';
import '../features/settings/settings_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Between pages ([PageFadeThrough]): the page leaving is hidden on the
/// first frame and the new one fades in, so two layouts are never on screen
/// at once. (`go` removes the old page, and a removed page stays painted
/// under the new one until the new one's transition ends — so it has to
/// hide itself.) Under reduced motion the route takes no time at all: a
/// route still running holds the new page offstage for its first frame (the
/// hero check) while the old one is already hidden — a blank frame.
Page<void> fadeThroughPage(BuildContext context, GoRouterState state, Widget child) {
  final duration = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : PageFadeThrough.duration;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        PageFadeThrough(animation: animation, secondaryAnimation: secondaryAnimation, child: child),
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      ShellRoute(
        pageBuilder: (context, state, child) => fadeThroughPage(context, state, LibraryShell(child: child)),
        routes: [
          GoRoute(path: '/', pageBuilder: (c, s) => fadeThroughPage(c, s, const HomeScreen())),
          GoRoute(
            path: '/scripts',
            pageBuilder: (c, s) => fadeThroughPage(c, s, const ScriptListScreen(filter: LibraryFilter.all())),
          ),
          GoRoute(
            path: '/archive',
            pageBuilder: (c, s) => fadeThroughPage(c, s, const ScriptListScreen(filter: LibraryFilter.archive())),
          ),
          GoRoute(
            path: '/collections/:id',
            // One route for every collection (the page key is the path
            // pattern), so switching between them fades the content in.
            pageBuilder: (c, s) => fadeThroughPage(
              c,
              s,
              ContentFadeIn(
                key: ValueKey(s.pathParameters['id']),
                child: ScriptListScreen(filter: LibraryFilter.collection(s.pathParameters['id']!)),
              ),
            ),
          ),
          GoRoute(path: '/sessions', pageBuilder: (c, s) => fadeThroughPage(c, s, const SessionsScreen())),
          GoRoute(path: '/chat', pageBuilder: (c, s) => fadeThroughPage(c, s, const ChatScreen())),
          GoRoute(path: '/forms', pageBuilder: (c, s) => fadeThroughPage(c, s, const FormsScreen())),
        ],
      ),
      GoRoute(
        path: '/script/:id',
        pageBuilder: (c, s) => fadeThroughPage(
          c,
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
        pageBuilder: (c, s) => fadeThroughPage(
          c,
          s,
          SettingsScreen(page: SettingsPage.values.asNameMap()[s.pathParameters['page']] ?? SettingsPage.shortcuts),
        ),
      ),
    ],
  );
});
