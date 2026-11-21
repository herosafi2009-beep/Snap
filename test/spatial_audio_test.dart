import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap/core/services/spatial_audio.dart';
import 'package:snap/features/settings/settings_pages.dart';

Widget host(SpatialAudioStatus status) => ProviderScope(
      overrides: [spatialAudioProvider.overrideWith((ref) => Stream.value(status))],
      child: const MaterialApp(home: Scaffold(body: SpatialAudioTile())),
    );

void main() {
  group('status from the platform', () {
    test('missing or unknown fields read as off', () {
      const empty = SpatialAudioStatus();
      expect(empty.platformSupported, isFalse);
      expect(empty.active, isFalse);
      expect(SpatialAudioStatus.fromMap(const {}), empty);
      expect(SpatialAudioStatus.fromMap(const {'available': 'yes'}).available, isFalse);
    });

    test('a device that can spatialize but has it switched off is not active', () {
      final status = SpatialAudioStatus.fromMap(const {
        'platformSupported': true,
        'available': true,
        'enabled': false,
      });
      expect(status.available, isTrue);
      expect(status.active, isFalse);
    });

    test('active needs both available and enabled', () {
      final status = SpatialAudioStatus.fromMap(const {
        'platformSupported': true,
        'available': true,
        'enabled': true,
        'headTracking': true,
        'multichannel': true,
      });
      expect(status.active, isTrue);
      expect(status.headTracking, isTrue);
      expect(status.multichannel, isTrue);
    });
  });

  group('what the setting says', () {
    testWidgets('an older Android says so plainly', (tester) async {
      await tester.pumpWidget(host(const SpatialAudioStatus()));
      await tester.pump();
      expect(find.text('Spatial audio'), findsOneWidget);
      expect(find.text('Not supported on this Android version'), findsOneWidget);
    });

    testWidgets('an output that cannot spatialize is not claimed to', (tester) async {
      await tester.pumpWidget(host(const SpatialAudioStatus(platformSupported: true)));
      await tester.pump();
      expect(find.text('Not supported by the current output'), findsOneWidget);
    });

    testWidgets('available but switched off points at system settings', (tester) async {
      await tester.pumpWidget(host(const SpatialAudioStatus(platformSupported: true, available: true)));
      await tester.pump();
      expect(find.text('Available, switched off in system settings'), findsOneWidget);
    });

    testWidgets('multichannel is mentioned only when the output keeps it', (tester) async {
      await tester.pumpWidget(host(const SpatialAudioStatus(
        platformSupported: true,
        available: true,
        enabled: true,
        multichannel: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Enabled by the system'), findsOneWidget);
      expect(find.text('Multichannel and Dolby Atmos content stays multichannel'), findsOneWidget);
      expect(find.text('Head tracking available'), findsNothing);
    });

    testWidgets('head tracking is mentioned only when the headphones have it', (tester) async {
      await tester.pumpWidget(host(const SpatialAudioStatus(
        platformSupported: true,
        available: true,
        enabled: true,
        headTracking: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Enabled by the system'), findsOneWidget);
      expect(find.text('Head tracking available'), findsOneWidget);
      expect(find.text('Multichannel and Dolby Atmos content stays multichannel'), findsNothing);
    });

  });
}
