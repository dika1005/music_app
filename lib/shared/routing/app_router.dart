import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:music_app/features/home/presentation/pages/home_page.dart';
import 'package:music_app/features/library/presentation/pages/library_page.dart';
import 'package:music_app/features/search/presentation/pages/search_page.dart';
import 'package:music_app/shared/widgets/connectivity_banner.dart';
import 'package:music_app/shared/widgets/player_views.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomePage()),
        GoRoute(
          path: '/search',
          builder: (_, state) => SearchPage(initialQuery: state.uri.queryParameters['q']),
        ),
        GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
      ],
    ),
  ],
);

/// Shell adaptif: NavigationBar di HP, NavigationRail di tablet.
/// MiniPlayer selalu di atas nav.
/// Back button: kembali ke Home dulu, baru keluar setelah double-tap.
class AppShell extends StatefulWidget {
  final Widget child;
  final int initialIndex;
  const AppShell({super.key, required this.child, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _tabs = ['/home', '/search', '/library'];
  DateTime? _lastBackPress;

  void _go(BuildContext context, int i) {
    // Item 3.4: feedback haptik ringan saat pindah tab.
    HapticFeedback.selectionClick();
    try {
      context.go(_tabs[i]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    int current = widget.initialIndex;
    try {
      final location = GoRouterState.of(context).uri.toString();
      final found = _tabs.indexWhere(location.startsWith);
      if (found >= 0) current = found;
    } catch (_) {
      current = widget.initialIndex;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Jika bukan di Home, kembali ke Home
        if (current != 0) {
          _go(context, 0);
          return;
        }
        // Di Home: double-back to exit
        final now = DateTime.now();
        if (_lastBackPress != null && now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastBackPress = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tekan sekali lagi untuk keluar'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 600;
        final body = Column(children: [
          Expanded(child: widget.child),
          // Item 5.4: strip offline global tepat di atas MiniPlayer. Diposisikan
          // di sini (bukan di atas konten) supaya tidak dobel padding SafeArea
          // dan tidak menggeser konten utama saat muncul/hilang.
          const ConnectivityBanner(),
          const MiniPlayer(),
        ]);
        if (wide) {
          return Scaffold(
            body: Row(children: [
              NavigationRail(
                selectedIndex: current,
                onDestinationSelected: (i) => _go(context, i),
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: Text('Home'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.search_outlined),
                    selectedIcon: Icon(Icons.search_rounded),
                    label: Text('Search'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music_rounded),
                    label: Text('Library'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ]),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0x14FFFFFF), width: 1),
              ),
            ),
            child: NavigationBar(
              height: 68,
              // Item 6.3: transisi tab lebih ringkas dari default M3 (500ms).
              animationDuration: const Duration(milliseconds: 400),
              selectedIndex: current,
              onDestinationSelected: (i) => _go(context, i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search_rounded),
                  label: 'Search',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded),
                  label: 'Library',
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
