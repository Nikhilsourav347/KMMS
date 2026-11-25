import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sembast/sembast.dart';

import 'domain.dart';

class MillError implements Exception {
  const MillError(this.message);
  final String message;
}

class AccountSetup {
  const AccountSetup(this.name, this.email, this.password);
  final String name, email, password;
}

class RecoveryKey {
  const RecoveryKey(this.role, this.value);
  final StaffRole role;
  final String value;
}

final _accounts = stringMapStoreFactory.store('accounts');
const _sessionKey = 'ukm.offline.session';
final _random = Random.secure();

List<int> _randomBytes(int count) =>
    List.generate(count, (_) => _random.nextInt(256));
String _token(int count) =>
    base64UrlEncode(_randomBytes(count)).replaceAll('=', '');
String normalizedEmail(String email) => email.trim().toLowerCase();
bool validEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

Future<List<int>> _passwordHash((String, String, int) input) async {
  final key =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: input.$3,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(input.$1)),
        nonce: base64Url.decode(input.$2),
      );
  return key.extractBytes();
}

Future<String> _recoveryHash(String code) async =>
    base64UrlEncode((await Sha256().hash(utf8.encode(code.trim()))).bytes);

bool _equal(String expected, String actual) {
  if (expected.length != actual.length) return false;
  var difference = 0;
  for (var i = 0; i < actual.length; i++) {
    difference |= expected.codeUnitAt(i) ^ actual.codeUnitAt(i);
  }
  return difference == 0;
}

class LocalAuth {
  LocalAuth(
    this.database, {
    this.storage = const FlutterSecureStorage(),
    this.rounds = 600000,
  });
  final Database database;
  final FlutterSecureStorage? storage;
  final int rounds;
  Staff? currentStaff;
  String? currentEmail;
  String? _currentSession;

  Future<bool> get hasAccounts async => await _accounts.count(database) > 0;

  Future<Map<String, Object?>> _credentials(String password) async {
    final salt = base64UrlEncode(_randomBytes(18));
    return {
      'salt': salt,
      'rounds': rounds,
      'password': base64UrlEncode(
        await compute(_passwordHash, (password, salt, rounds)),
      ),
    };
  }

  Future<List<RecoveryKey>> setup(AccountSetup admin) async {
    final email = normalizedEmail(admin.email);
    if (admin.name.trim().isEmpty ||
        !validEmail(email) ||
        admin.password.length < 12) {
      throw const MillError(
        'Enter a name, valid email and password with at least 12 characters.',
      );
    }
    final key = _token(18);
    final credentials = await _credentials(admin.password);
    final recovery = await _recoveryHash(key);
    await database.transaction((txn) async {
      if (await _accounts.count(txn) != 0) {
        throw const MillError('Staff accounts are already set up.');
      }
      await _accounts.record(email).put(txn, {
        'role': StaffRole.admin.name,
        'full_name': admin.name.trim(),
        ...credentials,
        'recovery': recovery,
      });
    });
    return [RecoveryKey(StaffRole.admin, key)];
  }

  Future<Staff?> restore() async {
    if (kIsWeb) return null;
    final encoded = await storage?.read(key: _sessionKey);
    if (encoded == null) return null;
    final parts = encoded.split('|');
    if (parts.length != 2) return null;
    final account = await _accounts.record(parts.first).get(database);
    if (account == null ||
        account['disabled'] == true ||
        account['session'] != parts.last) {
      return null;
    }
    currentEmail = parts.first;
    _currentSession = parts.last;
    return currentStaff = Staff.fromRow(account);
  }

  Future<Staff> signIn(String email, String password, {StaffRole? role}) async {
    final identity = normalizedEmail(email);
    final account = await _accounts.record(identity).get(database);
    if (account == null) {
      throw const MillError('The work email or password is incorrect.');
    }
    final hash = base64UrlEncode(
      await compute(_passwordHash, (
        password,
        account['salt'] as String,
        account['rounds'] as int,
      )),
    );
    if (account['disabled'] == true ||
        (role != null && account['role'] != role.name) ||
        !_equal(account['password'] as String, hash)) {
      throw const MillError('The work email or password is incorrect.');
    }
    final session = _token(24);
    await database.transaction((txn) async {
      final saved = await _accounts.record(identity).get(txn);
      if (saved?['password'] != account['password'] ||
          saved?['disabled'] == true) {
        throw const MillError('The password changed. Sign in again.');
      }
      await _accounts.record(identity).update(txn, {'session': session});
    });
    if (!kIsWeb) {
      await storage?.write(key: _sessionKey, value: '$identity|$session');
    }
    currentEmail = identity;
    _currentSession = session;
    return currentStaff = Staff.fromRow(account);
  }

  Future<void> signOut() async {
    final identity = currentEmail;
    final session = _currentSession;
    if (identity != null) {
      await database.transaction((txn) async {
        final row = await _accounts.record(identity).get(txn);
        if (row?['session'] == session) {
          await _accounts.record(identity).update(txn, {'session': null});
        }
      });
    }
    currentStaff = null;
    currentEmail = null;
    _currentSession = null;
    if (!kIsWeb) await storage?.delete(key: _sessionKey);
  }

  Future<RowData> authorize(DatabaseClient client, {StaffRole? role}) async {
    final email = currentEmail;
    final stored = email == null
        ? null
        : await _accounts.record(email).get(client);
    if (stored == null ||
        stored['disabled'] == true ||
        _currentSession == null ||
        stored['session'] != _currentSession ||
        (role != null && stored['role'] != role.name)) {
      throw const MillError(
        'An active account with the required role is needed.',
      );
    }
    return stored;
  }

  RowData _publicProfile(String email, RowData row) => {
    'email': email,
    'full_name': row['full_name'],
    'phone': row['phone'] ?? '',
    'role': row['role'],
    'disabled': row['disabled'] == true,
    'mill_id': 'unique-knitting-mills',
  };

  Future<RowData> profile() async =>
      _publicProfile(currentEmail ?? '', await authorize(database));

  Future<void> editProfile(String name, String email, String phone) async {
    final identity = normalizedEmail(email);
    final oldEmail = currentEmail;
    if (name.trim().isEmpty || !validEmail(identity)) {
      throw const MillError('Enter a name and valid email address.');
    }
    final updated = await database.transaction((txn) async {
      final current = await authorize(txn);
      final next = {
        ...current,
        'full_name': name.trim(),
        'phone': phone.trim(),
      };
      if (identity != oldEmail) {
        if (await _accounts.record(identity).exists(txn)) {
          throw const MillError('That email is already registered.');
        }
        await _accounts.record(oldEmail!).delete(txn);
      }
      await _accounts.record(identity).put(txn, next);
      return next;
    });
    currentEmail = identity;
    currentStaff = Staff.fromRow(updated);
    if (!kIsWeb) {
      await storage?.write(
        key: _sessionKey,
        value: '$identity|$_currentSession',
      );
    }
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    if (newPassword.length < 12) {
      throw const MillError('Use at least 12 characters.');
    }
    final current = await authorize(database);
    final input = await compute(_passwordHash, (
      currentPassword,
      current['salt'] as String,
      current['rounds'] as int,
    ));
    if (!_equal(current['password'] as String, base64UrlEncode(input))) {
      throw const MillError('The current password is incorrect.');
    }
    final credentials = await _credentials(newPassword);
    await database.transaction((txn) async {
      final latest = await authorize(txn);
      if (latest['password'] != current['password']) {
        throw const MillError('The password changed. Try again.');
      }
      await _accounts.record(currentEmail!).update(txn, credentials);
    });
  }

  Future<RecoveryKey> addAccount(
    StaffRole role,
    AccountSetup account, {
    String phone = '',
  }) async {
    await authorize(database, role: StaffRole.admin);
    final email = normalizedEmail(account.email);
    if (account.name.trim().isEmpty ||
        !validEmail(email) ||
        account.password.length < 12) {
      throw const MillError(
        'Enter a name, valid email and password with at least 12 characters.',
      );
    }
    final key = _token(18);
    final credentials = await _credentials(account.password);
    final recovery = await _recoveryHash(key);
    await database.transaction((txn) async {
      await authorize(txn, role: StaffRole.admin);
      if (await _accounts.record(email).exists(txn)) {
        throw const MillError('That email is already registered.');
      }
      await _accounts.record(email).put(txn, {
        'role': role.name,
        'full_name': account.name.trim(),
        'phone': phone.trim(),
        ...credentials,
        'recovery': recovery,
      });
    });
    return RecoveryKey(role, key);
  }

  Future<List<RowData>> managers() async {
    await authorize(database, role: StaffRole.admin);
    final records = await _accounts.find(database);
    return [
      for (final record in records)
        if (record.value['role'] == StaffRole.manager.name)
          _publicProfile(record.key, record.value),
    ];
  }

  Future<void> setManagerEnabled(String email, bool enabled) async {
    await database.transaction((txn) async {
      await authorize(txn, role: StaffRole.admin);
      final record = _accounts.record(normalizedEmail(email));
      if ((await record.get(txn))?['role'] != StaffRole.manager.name) {
        throw const MillError('Manager account is unavailable.');
      }
      await record.update(txn, {
        'disabled': !enabled,
        if (!enabled) 'session': null,
      });
    });
  }

  Future<String> recover(String email, String code, String newPassword) async {
    if (newPassword.length < 12) {
      throw const MillError(
        'Use at least 12 characters for your new password.',
      );
    }
    final identity = normalizedEmail(email);
    final account = await _accounts.record(identity).get(database);
    final supplied = await _recoveryHash(code);
    if (account == null || !_equal(account['recovery'] as String, supplied)) {
      throw const MillError('The work email or recovery key is incorrect.');
    }
    final replacement = _token(18);
    final credentials = await _credentials(newPassword);
    final replacementHash = await _recoveryHash(replacement);
    await database.transaction((txn) async {
      final saved = await _accounts.record(identity).get(txn);
      if (saved?['recovery'] != account['recovery']) {
        throw const MillError('This recovery key has already been used.');
      }
      await _accounts.record(identity).update(txn, {
        ...credentials,
        'recovery': replacementHash,
        'session': null,
      });
    });
    return replacement;
  }
}
