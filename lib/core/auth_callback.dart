import 'package:supabase_flutter/supabase_flutter.dart';

/// Normalize Supabase parameters before Flutter can interpret the fragment as
/// a navigation route. Supports both direct callbacks and hash-route URLs.
Uri? parseAuthCallback(Uri uri) {
  final fragment = uri.fragment;
  final separator = fragment.indexOf('?');
  final fragmentQuery = fragment.startsWith('/')
      ? (separator < 0 ? '' : fragment.substring(separator + 1))
      : fragment;
  final parameters = {
    ...Uri.splitQueryString(fragmentQuery),
    ...uri.queryParameters,
  };
  if (!parameters.keys.any(
    const {
      'token_hash',
      'code',
      'access_token',
      'error_code',
      'error',
    }.contains,
  )) {
    return null;
  }
  return uri.replace(queryParameters: parameters, fragment: '');
}

Future<Session?> exchangeAuthCallback(GoTrueClient auth, Uri callback) async {
  final parameters = callback.queryParameters;
  // Give server errors precedence over tokens on the same URL.
  if (parameters.containsKey('error') || parameters.containsKey('error_code')) {
    throw AuthException(
      'The verification link could not be accepted.',
      code: parameters['error_code'] ?? parameters['error'],
    );
  }
  Session? recoverySession;
  final events = auth.onAuthStateChange.listen((state) {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      recoverySession = state.session;
    }
  }, onError: (Object _) {});
  try {
    final hash = parameters['token_hash'];
    if (hash != null) {
      if (hash.isEmpty || parameters['type'] != 'recovery') {
        throw const AuthException('Invalid recovery token.');
      }
      final response = await auth.verifyOTP(
        tokenHash: hash,
        type: OtpType.recovery,
      );
      final verified = recoverySession ?? response.session;
      if (verified == null) {
        throw const AuthException('Missing recovery session.');
      }
      return verified;
    }
    final response = await auth.getSessionFromUrl(callback);
    if (response.redirectType == 'recovery' ||
        response.redirectType == AuthChangeEvent.passwordRecovery.name) {
      return recoverySession ?? response.session;
    }
    return recoverySession;
  } finally {
    await events.cancel();
  }
}
