import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniexam/config/theme.dart';
import 'package:uniexam/features/teacher/settings_screen.dart';
import 'package:uniexam/models/user.dart';
import 'package:uniexam/providers/auth_provider.dart';
import 'package:uniexam/providers/providers.dart';

import 'fakes.dart';

class _SignedIn extends AuthNotifier {
  _SignedIn(this.user);
  final User user;
  @override
  AuthState build() => AuthState(status: AuthStatus.authenticated, user: user);
}

const _admin = User(id: 1, userId: 'admin', name: 'Admin', role: UserRole.admin);

Widget wrap(FakeSettingsRepository settings) => ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _SignedIn(_admin)),
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SettingsScreen(),
      ),
    );

void main() {
  testWidgets('it shows the name the installation currently carries', (tester) async {
    final settings = FakeSettingsRepository(universityName: 'Khulna University');
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    expect(find.text('Khulna University'), findsWidgets);
    expect(
      find.textContaining('every result sheet and statement of result'),
      findsOneWidget,
    );
  });

  testWidgets('an admin changes it', (tester) async {
    final settings = FakeSettingsRepository(universityName: 'University');
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('university_name')),
      'Rajshahi University of Engineering & Technology',
    );
    await tester.tap(find.byKey(const Key('save_settings')));
    await tester.pumpAndSettle();

    expect(settings.saved, ['Rajshahi University of Engineering & Technology']);
    expect(find.textContaining('Reports will carry the new name'), findsOneWidget);
  });

  testWidgets('it will not save an empty name', (tester) async {
    // It is printed at the top of every official document; a blank header is worse
    // than the placeholder it replaced.
    final settings = FakeSettingsRepository();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('university_name')), '   ');
    await tester.tap(find.byKey(const Key('save_settings')));
    await tester.pumpAndSettle();

    expect(find.text('Enter the name of the university'), findsOneWidget);
    expect(settings.saved, isEmpty);
  });

  testWidgets('it will not save one too long for a document header', (tester) async {
    final settings = FakeSettingsRepository();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('university_name')), 'A' * 151);
    await tester.tap(find.byKey(const Key('save_settings')));
    await tester.pumpAndSettle();

    expect(find.textContaining('150 characters'), findsOneWidget);
    expect(settings.saved, isEmpty);
  });

  testWidgets('typing does not fight the cursor', (tester) async {
    // The field is seeded once from the loaded value. Re-seeding on every rebuild
    // would move the caret back to the start mid-word.
    final settings = FakeSettingsRepository(universityName: 'University');
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('university_name')), 'Dhaka Uni');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Dhaka Uni'), findsOneWidget);
  });
}
