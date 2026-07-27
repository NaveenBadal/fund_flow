import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fund_flow/update/app_updater.dart';
import 'package:fund_flow/zero/zero_theme.dart';
import 'package:fund_flow/zero/zero_update.dart';

void main() {
  testWidgets('current release presents a quiet completed state', (
    tester,
  ) async {
    await _pump(tester, availability: UpdateAvailability.current);

    expect(find.text('Fund Flow is current'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Download and verify'), findsNothing);
  });

  testWidgets('available release separates download from installation', (
    tester,
  ) async {
    await _pump(tester, availability: UpdateAvailability.available);

    expect(find.text('1.2.3 · build 42'), findsOneWidget);
    expect(find.text('What’s new'), findsOneWidget);
    expect(find.text('A calmer release.'), findsOneWidget);
    expect(find.text('Download and verify'), findsOneWidget);
    expect(find.text('Install verified update'), findsNothing);
  });

  testWidgets('unsupported channel explains who manages updates', (
    tester,
  ) async {
    await _pump(tester, availability: UpdateAvailability.unsupported);

    expect(find.text('Managed by your release channel'), findsOneWidget);
    expect(find.text('Download and verify'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required UpdateAvailability availability,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ZeroTheme.light(),
      home: Scaffold(
        body: ZeroUpdateSheet(
          updater: _FakeUpdater(
            AppUpdate(
              availability: availability,
              versionName: '1.2.3',
              buildNumber: 42,
              installedBuildNumber: 41,
              releaseNotes: 'A calmer release.',
              publishedAt: DateTime(2026, 7, 27),
              apkUrl: Uri.parse(
                'https://github.com/NaveenBadal/fund_flow/releases/download/a.apk',
              ),
              sha256:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              mandatory: false,
              downloadSize: 20 * 1024 * 1024,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeUpdater extends AppUpdater {
  _FakeUpdater(this.result);
  final AppUpdate result;

  @override
  Future<AppUpdate> check({dynamic installedPackage}) async => result;
}
