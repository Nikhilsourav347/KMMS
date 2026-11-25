import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ukm/core/auth_callback.dart';

class _VerifierStorage implements GotrueAsyncStorage {
  final values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

void main() {
  final user = {
    'id': 'fixture',
    'aud': 'authenticated',
    'email': 'staff@example.invalid',
    'created_at': '2026-11-26T00:00:00Z',
    'app_metadata': <String, Object>{},
  };
  final session = {
    'access_token': 'fixture-access-token',
    'refresh_token': 'fixture-refresh-token',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': user,
  };
  http.Response jsonResponse(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('normalizes direct recovery and Flutter hash routes', () {
    final route = parseAuthCallback(
      Uri.parse(
        'https://app.invalid/KMMS/#/reset?type=recovery&token_hash=a%2Bb',
      ),
    );
    expect(route?.queryParameters['token_hash'], 'a+b');
    expect(route?.queryParameters['type'], 'recovery');
    expect(route?.fragment, isEmpty);
    expect(
      parseAuthCallback(Uri.parse('https://app.invalid/KMMS/#/profile')),
      isNull,
    );
  });

  test(
    'verifies a recovery token once without a browser-local verifier',
    () async {
      var calls = 0;
      final auth = GoTrueClient(
        url: 'https://auth.invalid',
        autoRefreshToken: false,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/verify');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['type'], 'recovery');
          expect(body['token_hash'], 'valid-fixture');
          expect(body.containsKey('code_verifier'), isFalse);
          if (++calls == 1) return jsonResponse(session);
          return jsonResponse({
            'code': 'otp_expired',
            'msg': 'Token expired',
          }, 403);
        }),
      );
      addTearDown(auth.dispose);
      final callback = parseAuthCallback(
        Uri.parse(
          'https://app.invalid/KMMS/?type=recovery&token_hash=valid-fixture',
        ),
      )!;
      final event = auth.onAuthStateChange.firstWhere(
        (state) => state.event == AuthChangeEvent.passwordRecovery,
      );
      expect((await exchangeAuthCallback(auth, callback))?.user.id, 'fixture');
      expect((await event).session?.user.id, 'fixture');
      expect(calls, 1);
      await expectLater(
        exchangeAuthCallback(auth, callback),
        throwsA(isA<AuthException>()),
      );
      expect(calls, 2);
    },
  );

  test('uses a saved verifier for old PKCE recovery links', () async {
    final storage = _VerifierStorage();
    final auth = GoTrueClient(
      url: 'https://auth.invalid',
      autoRefreshToken: false,
      asyncStorage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path == '/recover') return jsonResponse({});
        expect(request.url.queryParameters['grant_type'], 'pkce');
        expect(jsonDecode(request.body)['auth_code'], 'old-link');
        expect(jsonDecode(request.body)['code_verifier'], isNotEmpty);
        return jsonResponse(session);
      }),
    );
    addTearDown(auth.dispose);
    final callback = parseAuthCallback(
      Uri.parse('https://app.invalid/KMMS/?code=old-link'),
    )!;
    await expectLater(
      exchangeAuthCallback(auth, callback),
      throwsA(isA<AuthException>()),
    );
    await auth.resetPasswordForEmail('staff@example.invalid');
    expect((await exchangeAuthCallback(auth, callback))?.user.id, 'fixture');
    expect(storage.values, isEmpty);
  });

  test(
    'handles recovery fragments and ignores server errors before verification',
    () async {
      var calls = 0;
      final auth = GoTrueClient(
        url: 'https://auth.invalid',
        autoRefreshToken: false,
        httpClient: MockClient((request) async {
          calls++;
          expect(request.url.path, '/user');
          return jsonResponse(user);
        }),
      );
      addTearDown(auth.dispose);
      final callback = parseAuthCallback(
        Uri.parse(
          'https://app.invalid/KMMS/#access_token=abc&refresh_token=def&expires_in=3600&token_type=bearer&type=recovery',
        ),
      )!;
      expect((await exchangeAuthCallback(auth, callback))?.user.id, 'fixture');
      final failed = parseAuthCallback(
        Uri.parse(
          'https://app.invalid/KMMS/#error_code=otp_expired&token_hash=abc&type=recovery',
        ),
      )!;
      await expectLater(
        exchangeAuthCallback(auth, failed),
        throwsA(isA<AuthException>()),
      );
      expect(calls, 1);
    },
  );
}
