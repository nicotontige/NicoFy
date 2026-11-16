import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/utilities/flutter_bottom_sheet.dart';

/// Built like the app: a shell with its own Scaffold around one navigator per
/// tab, and a tab page with its Scaffold, opening a sheet from its own context
/// the way the settings pickers do.
GoRouter _router(void Function(BuildContext) onPick) {
  final rootKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/settings',
    routes: [
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: rootKey,
        builder: (context, state, shell) => Scaffold(body: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => _SettingsLikePage(onPick),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _SettingsLikePage extends StatelessWidget {
  const _SettingsLikePage(this.onPick);

  final void Function(BuildContext) onPick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('settings page'),
          TextButton(
            onPressed: () => showCustomBottomSheet(
              context,
              TextButton(
                onPressed: () => onPick(context),
                child: const Text('dark'),
              ),
            ),
            child: const Text('theme'),
          ),
        ],
      ),
    );
  }
}

Future<void> _openAndPick(
  WidgetTester tester,
  void Function(BuildContext) onPick,
) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router(onPick)));
  await tester.tap(find.text('theme'));
  await tester.pumpAndSettle();
  expect(isBottomSheetOpen.value, isTrue);

  await tester.tap(find.text('dark'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('picking an option closes the sheet and keeps the page', (
    tester,
  ) async {
    await _openAndPick(tester, (_) => closeCurrentBottomSheet());

    expect(find.text('dark'), findsNothing);
    expect(isBottomSheetOpen.value, isFalse);
    expect(find.text('settings page'), findsOneWidget);
  });

  testWidgets('the drag handle closes the sheet and keeps the page', (
    tester,
  ) async {
    await _openAndPick(tester, (_) {});
    expect(find.text('dark'), findsOneWidget);

    // The handle is the small bar at the top centre of the sheet.
    final sheet = tester.getRect(find.byType(BottomSheet));
    await tester.tapAt(Offset(sheet.center.dx, sheet.top + 14));
    await tester.pumpAndSettle();

    expect(find.text('dark'), findsNothing);
    expect(find.text('settings page'), findsOneWidget);
  });
}
