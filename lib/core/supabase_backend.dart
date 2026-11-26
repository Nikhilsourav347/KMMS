import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'domain.dart';
import 'auth.dart';
import 'auth_callback.dart';
import 'auth_url.dart';
import 'repository.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _connectionError = MillError(
  'Could not connect to Supabase. Check your internet connection and try again.',
);
const _authTimeout = Duration(seconds: 12);
bool _handledRecovery = false;

Future<MillData> openSupabaseBackend({Uri? launchUri}) async {
  final callback = parseAuthCallback(launchUri ?? Uri.base);
  final endpoint = Uri.tryParse(_url);
  if (endpoint == null ||
      endpoint.scheme != 'https' ||
      endpoint.host.isEmpty ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      !_isClientKey(_key)) {
    throw const MillError(
      'Configure an HTTPS Supabase URL and publishable key.',
    );
  }
  try {
    final response = await http
        .get(
          endpoint.replace(path: '/auth/v1/settings'),
          headers: {'apikey': _key},
        )
        .timeout(_authTimeout);
    if (response.statusCode != 200) throw _connectionError;
  } on http.ClientException {
    throw _connectionError;
  } on TimeoutException {
    throw _connectionError;
  }
  final supabase = await Supabase.initialize(
    url: _url,
    publishableKey: _key,
    authOptions: FlutterAuthClientOptions(
      detectSessionInUri: false,
      localStorage: kIsWeb
          ? null
          : _NativeCloudSession('ukm.supabase.${endpoint.host}'),
    ),
  );
  final client = supabase.client;
  final preferences = SharedPreferencesAsync();
  final recoveryKey = 'ukm_password_recovery_${endpoint.host}';
  String? recoveryError;
  if (!_handledRecovery && callback != null) {
    try {
      final session = await exchangeAuthCallback(client.auth, callback);
      if (session == null) {
        await preferences.remove(recoveryKey);
      } else {
        final sessionId = _sessionIdentifier(session);
        if (sessionId == null) {
          await client.auth.signOut(scope: SignOutScope.local);
          throw const AuthException('Missing recovery session identifier.');
        }
        await preferences.setString(recoveryKey, sessionId);
      }
    } on AuthRetryableFetchException {
      throw _connectionError;
    } on TimeoutException {
      throw _connectionError;
    } on AuthException catch (error) {
      final missingVerifier =
          callback.queryParameters.containsKey('code') &&
          (error.code == 'bad_code_verifier' ||
              error.message ==
                  'Code verifier could not be found in local storage.');
      recoveryError = missingVerifier
          ? 'Request a new reset link. Older links must be opened in the browser that requested them.'
          : 'This recovery link is invalid, expired, or already used. Request a new link.';
    } on FormatException {
      recoveryError =
          'This recovery link is invalid, expired, or already used. Request a new link.';
    }
    _handledRecovery = true;
    clearRecoveryUrl();
  }
  final recoverySession = await preferences.getString(recoveryKey);
  return SupabaseMill(
    client,
    recoveryPending:
        recoverySession != null &&
        recoverySession == _sessionIdentifier(client.auth.currentSession),
    recoveryError: recoveryError,
    clearRecovery: () => preferences.remove(recoveryKey),
  );
}

String? _sessionIdentifier(Session? session) {
  if (session == null) return null;
  try {
    final token = session.accessToken.split('.')[1];
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token))),
    );
    final sessionId = claims is RowData ? claims['session_id'] : null;
    return sessionId is String ? sessionId : null;
  } on FormatException {
    return null;
  } on RangeError {
    return null;
  }
}

bool _isClientKey(String key) {
  if (key.startsWith('sb_publishable_')) return true;
  try {
    final segments = key.split('.');
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
    );
    return segments.length == 3 &&
        claims is RowData &&
        claims['role'] == 'anon';
  } catch (_) {
    return false;
  }
}

class _NativeCloudSession extends LocalStorage {
  const _NativeCloudSession(this.key);
  final String key;
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: key);
  @override
  Future<String?> accessToken() => _storage.read(key: key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _storage.delete(key: key);
}

Future<T> _cloud<T>(Future<T> Function() run) async {
  try {
    return await run();
  } on PostgrestException catch (error) {
    if (error.code == 'P0001' || error.code == '42501') {
      throw MillError(error.message);
    }
    throw const MillError(
      'Supabase could not complete the request. Check the connection or project setup.',
    );
  } on AuthRetryableFetchException {
    throw _connectionError;
  } on http.ClientException {
    throw _connectionError;
  } on TimeoutException {
    throw _connectionError;
  } on AuthException catch (error) {
    if (error.code == 'email_not_confirmed') {
      throw const EmailVerificationRequired();
    }
    if (error.code == 'invalid_credentials') {
      throw const MillError('The email address or password is incorrect.');
    }
    throw MillError(error.message);
  } on FunctionException catch (error) {
    final body = error.details;
    throw MillError(
      body is RowData && body['message'] is String
          ? body['message'] as String
          : 'Staff provisioning is unavailable. Check its Supabase setup.',
    );
  }
}

class SupabaseMill implements MillData {
  SupabaseMill(
    this.client, {
    required bool recoveryPending,
    required String? recoveryError,
    required Future<void> Function() clearRecovery,
  }) : auth = SupabaseMillAuth(
         client,
         recoveryPending: recoveryPending,
         recoveryError: recoveryError,
         clearRecovery: clearRecovery,
       ) {
    _session = client.auth.onAuthStateChange.listen((event) {
      if (event.session == null) {
        final channel = _channel;
        _channel = null;
        if (channel != null) unawaited(client.removeChannel(channel));
      } else {
        _subscribe();
      }
    }, onError: (Object _) {});
    if (client.auth.currentSession != null) _subscribe();
  }

  final SupabaseClient client;
  @override
  final SupabaseMillAuth auth;
  final _changes = StreamController<(Dataset, int)>.broadcast();
  final _machineStatuses = StreamController<MachineStatusUpdate?>.broadcast();
  late final StreamSubscription<AuthState> _session;
  RealtimeChannel? _channel;
  int _revision = 0;

  @override
  Stream<int> updates(Dataset dataset) => _changes.stream
      .where((event) => event.$1 == dataset)
      .map((event) => event.$2);

  @override
  Stream<MachineStatusUpdate?> get machineStatusUpdates =>
      _machineStatuses.stream;

  void _changed(Iterable<Dataset> datasets) {
    if (!_changes.isClosed) {
      for (final dataset in datasets) {
        _changes.add((dataset, ++_revision));
      }
    }
  }

  void _machineStatusChanged([MachineStatusUpdate? update]) {
    if (!_machineStatuses.isClosed) _machineStatuses.add(update);
  }

  MachineStatus _status(RowData row) =>
      (running: row['running'] == true, revision: row['revision'] as int);

  void _recordChanged(String table, PostgresChangePayload payload) {
    switch (table) {
      case 'daily_machine_status':
        final row = payload.newRecord;
        final id = row['machine_id'];
        final date = row['date'];
        if (id is int && date is String && row['revision'] is int) {
          _machineStatusChanged((id: id, date: date, status: _status(row)));
        } else {
          _machineStatusChanged();
        }
      case 'machine_status' || 'machine_status_history':
        _machineStatusChanged();
      case 'machines':
        _changed([Dataset.machines, Dataset.schedule]);
        _machineStatusChanged();
      case 'schedules':
        _changed([Dataset.schedule]);
      case 'production_entries' ||
          'jobs' ||
          'job_programs' ||
          'parties' ||
          'specifications':
        _changed([Dataset.jobs, Dataset.production]);
    }
  }

  void _subscribe() {
    if (_channel != null) return;
    final channel = client.channel('ukm-mill-data');
    _channel = channel;
    for (final table in [
      'machines',
      'daily_machine_status',
      'machine_status',
      'machine_status_history',
      'schedules',
      'jobs',
      'job_programs',
      'production_entries',
      'parties',
      'specifications',
    ]) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (payload) => _recordChanged(table, payload),
      );
    }
    channel.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _changed(Dataset.values);
        _machineStatusChanged();
      }
    });
  }

  @override
  Future<void> close() async {
    await _session.cancel();
    await auth.close();
    final channel = _channel;
    _channel = null;
    if (channel != null) await client.removeChannel(channel);
    await _changes.close();
    await _machineStatuses.close();
  }

  Future<dynamic> _rpc(String name, [RowData? parameters]) =>
      _cloud(() async => await client.rpc(name, params: parameters));
  Future<void> _mutate(
    String name,
    RowData parameters,
    List<Dataset> datasets,
  ) async {
    await _rpc(name, parameters);
    _changed(datasets);
    if (datasets.contains(Dataset.machines)) _machineStatusChanged();
  }

  Future<List<RowData>> _pages(
    Future<List<RowData>> Function(int, int) fetch,
  ) async {
    const size = 250;
    final records = <RowData>[];
    for (var offset = 0; ; offset += size) {
      final page = await _cloud(() => fetch(offset, offset + size - 1));
      records.addAll(page);
      if (page.length < size) return records;
    }
  }

  @override
  Future<List<RowData>> registeredMachines() => _pages(
    (start, end) => client
        .from('machines')
        .select()
        .isFilter('removed_at', null)
        .order('name')
        .order('id')
        .range(start, end),
  );

  @override
  Future<void> saveMachine({
    int? id,
    required String number,
    required String dia,
    String type = '',
    String specifications = '',
  }) => _mutate(
    'ukm_save_machine_label',
    {
      'p_id': id,
      'p_number': number,
      'p_dia_label': dia,
      'p_type': type,
      'p_specifications': specifications,
    },
    [Dataset.machines, Dataset.schedule],
  );

  @override
  Future<bool> removeMachine(int id) async {
    final deleted = await _rpc('ukm_remove_machine', {'p_id': id}) == true;
    _changed([Dataset.machines, Dataset.schedule]);
    _machineStatusChanged();
    return deleted;
  }

  @override
  Future<List<RowData>> machineDay(DateTime date) async =>
      rows(await _rpc('ukm_machine_day', {'p_date': isoDate(date)}));

  @override
  Future<MachineStatus> setRunning(int id, DateTime date, bool running) async {
    final day = isoDate(date);
    final status = _status(
      await _rpc('ukm_write_running', {
            'p_id': id,
            'p_date': day,
            'p_running': running,
          })
          as RowData,
    );
    _machineStatusChanged((id: id, date: day, status: status));
    return status;
  }

  @override
  Future<List<MachineScheduleRow>> machineSchedule(
    DateTime first,
    DateTime last,
  ) async => [
    for (final machine in rows(
      await _rpc('ukm_calendar', {
        'p_first': isoDate(first),
        'p_last': isoDate(last),
      }),
    ))
      (
        machine: machine,
        bookedDates: (machine['booked_dates'] as List).cast<String>().toSet(),
      ),
  ];

  @override
  Future<void> scheduleMachine(int id, DateTime date) =>
      _booking(id, date, true);
  @override
  Future<void> cancelMachineSchedule(int id, DateTime date) =>
      _booking(id, date, false);
  Future<void> _booking(int id, DateTime date, bool booked) => _mutate(
    'ukm_set_booking',
    {'p_id': id, 'p_date': isoDate(date), 'p_booked': booked},
    [Dataset.schedule],
  );

  @override
  Future<List<RowData>> names(String table) => _pages(
    (start, end) => client
        .from(table == 'parties' ? 'parties' : 'specifications')
        .select('id,name')
        .order('name')
        .order('id')
        .range(start, end),
  );

  @override
  Future<void> saveJob({
    RowData? existing,
    required DateTime date,
    required String number,
    required String party,
    required String yarn,
    required List<RowData> programs,
  }) => _mutate(
    'ukm_save_job',
    {
      'p_id': existing?['id'],
      'p_version': existing?['updated_at'],
      'p_date': isoDate(date),
      'p_number': number,
      'p_party': party,
      'p_yarn': yarn,
      'p_programs': programs,
    },
    [Dataset.jobs, Dataset.production],
  );

  @override
  Future<List<RowData>> jobs() => _pages(
    (start, end) => client
        .from('ukm_jobs')
        .select()
        .order('job_date', ascending: false)
        .order('id')
        .range(start, end),
  );

  @override
  Future<List<RowData>> programs(String jobId) => _pages(
    (start, end) => client
        .from('ukm_program_totals')
        .select()
        .eq('job_id', jobId)
        .order('position')
        .order('id')
        .range(start, end),
  );

  @override
  Future<RowData> productionSheet(
    String jobId,
    DateTime date,
    Shift shift,
  ) async =>
      await _rpc('ukm_production_sheet', {
            'p_job': jobId,
            'p_date': isoDate(date),
            'p_shift': shift.name,
          })
          as RowData;

  @override
  Future<void> saveProduction(
    String jobId,
    DateTime date,
    Shift shift,
    List<RowData> lines,
  ) => _mutate(
    'ukm_save_production',
    {
      'p_job': jobId,
      'p_date': isoDate(date),
      'p_shift': shift.name,
      'p_lines': lines,
    },
    [Dataset.jobs, Dataset.production],
  );

  @override
  Future<RowData> report({
    DateTime? start,
    DateTime? end,
    Shift? shift,
    String? jobId,
    String? partyId,
    String? dia,
  }) async =>
      await _rpc('ukm_report', {
            'p_start': start == null ? null : isoDate(start),
            'p_end': end == null ? null : isoDate(end),
            'p_shift': shift?.name,
            'p_job': jobId,
            'p_party': partyId,
            'p_dia': dia,
          })
          as RowData;

  @override
  Future<List<String>> reportDias(DateTime start, DateTime end) async =>
      (await _rpc('ukm_report_dias', {
                'p_start': isoDate(start),
                'p_end': isoDate(end),
              })
              as List)
          .cast<String>();
}

class SupabaseMillAuth implements MillAuth {
  SupabaseMillAuth(
    this.client, {
    required bool recoveryPending,
    required this.recoveryError,
    required this.clearRecovery,
  }) : _isPasswordRecovery = recoveryPending {
    _authEvents = client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        currentStaff = null;
        _isPasswordRecovery = false;
        _stateChanges.add(AuthFlow.signedOut);
      }
    }, onError: (Object _) {});
  }
  final SupabaseClient client;
  final _stateChanges = StreamController<AuthFlow>.broadcast();
  late final StreamSubscription<AuthState> _authEvents;
  bool _isPasswordRecovery;
  @override
  final String? recoveryError;
  final Future<void> Function() clearRecovery;

  @override
  Staff? currentStaff;
  @override
  bool get isPasswordRecovery => _isPasswordRecovery;
  @override
  Stream<AuthFlow> get stateChanges => _stateChanges.stream;

  Future<void> close() async {
    await _authEvents.cancel();
    await _stateChanges.close();
  }

  @override
  Future<Staff?> restore() async {
    if (isPasswordRecovery || client.auth.currentSession == null) return null;
    return _readStaff();
  }

  Future<Staff?> _readStaff() => _cloud(() async {
    final user = await client.rpc('ukm_profile').timeout(_authTimeout);
    if (user is! RowData) {
      await signOut();
      return null;
    }
    return currentStaff = Staff.fromRow(user);
  });

  @override
  Future<Staff> signIn(String email, String password, {StaffRole? role}) =>
      _cloud(() async {
        await client.auth
            .signInWithPassword(
              email: normalizedEmail(email),
              password: password,
            )
            .timeout(_authTimeout);
        final staff = await _readStaff();
        if (staff == null) {
          throw const MillError(
            'Ask an administrator to enable your staff profile.',
          );
        }
        if (role != null && staff.role != role) {
          await signOut();
          throw MillError('Use ${staff.role.label} Login for this account.');
        }
        return staff;
      });

  @override
  Future<void> signOut() => _cloud(() async {
    await client.auth.signOut(scope: SignOutScope.local);
    await clearRecovery();
    currentStaff = null;
  });

  @override
  Future<RowData> profile() => _cloud(() async {
    final row = await client.rpc('ukm_profile');
    if (row is! RowData) {
      throw const MillError('Your staff profile is unavailable.');
    }
    return row;
  });

  @override
  Future<void> editProfile(String name, String email, String phone) =>
      _cloud(() async {
        final user = client.auth.currentUser;
        if (user == null) throw const MillError('Sign in again.');
        if (!validEmail(email)) {
          throw const MillError('Enter a valid work email.');
        }
        await client.rpc(
          'ukm_edit_profile',
          params: {'p_name': name, 'p_phone': phone},
        );
        if (normalizedEmail(email) != normalizedEmail(user.email ?? '')) {
          await client.auth.updateUser(
            UserAttributes(email: normalizedEmail(email)),
          );
        }
        currentStaff = Staff.fromRow(await profile());
      });

  @override
  Future<void> changePassword(String currentPassword, String newPassword) =>
      _cloud(() async {
        if (newPassword.length < 12) {
          throw const MillError('Use at least 12 characters.');
        }
        final email = client.auth.currentUser?.email;
        if (email == null) throw const MillError('Sign in again.');
        await client.auth.signInWithPassword(
          email: email,
          password: currentPassword,
        );
        await client.auth.updateUser(UserAttributes(password: newPassword));
      });

  @override
  Future<bool> addAccount(
    StaffRole role,
    AccountSetup account, {
    String phone = '',
  }) => _cloud(() async {
    final token = client.auth.currentSession?.accessToken;
    if (token == null) throw const MillError('Sign in again.');
    final result = await client.functions.invoke(
      'ukm-create-account',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'role': role.name,
        'name': account.name,
        'email': normalizedEmail(account.email),
        'password': account.password,
        'phone': phone,
      },
    );
    return result.data is RowData &&
        result.data['verification_requested'] == true;
  });

  @override
  Future<List<RowData>> managers() =>
      _cloud(() async => rows(await client.rpc('ukm_managers')));

  @override
  Future<void> setManagerEnabled(String email, bool enabled) =>
      _cloud(() async {
        await client.rpc(
          'ukm_set_manager_enabled',
          params: {'p_email': email, 'p_enabled': enabled},
        );
      });

  @override
  Future<void> requestRecovery(String email) => _cloud(() async {
    if (!validEmail(email)) {
      throw const MillError('Enter your work email first.');
    }
    await client.auth.resetPasswordForEmail(normalizedEmail(email));
  });

  @override
  Future<void> requestEmailVerification(String email) => _cloud(() async {
    if (!validEmail(email)) throw const MillError('Enter a valid work email.');
    await client.auth.resend(
      type: OtpType.signup,
      email: normalizedEmail(email),
    );
  });

  @override
  Future<void> recoverWithCode(String email, String code, String password) =>
      _cloud(() async {
        if (!validEmail(email) || !RegExp(r'^\d{6,8}$').hasMatch(code.trim())) {
          throw const MillError('Enter your email address and recovery code.');
        }
        if (password.length < 12) {
          throw const MillError('Use at least 12 characters.');
        }
        await client.auth.verifyOTP(
          email: normalizedEmail(email),
          token: code.trim(),
          type: OtpType.recovery,
        );
        try {
          await client.auth.updateUser(UserAttributes(password: password));
        } finally {
          await signOut();
        }
      });

  @override
  Future<void> completeRecovery(String newPassword) => _cloud(() async {
    if (newPassword.length < 12) {
      throw const MillError('Use at least 12 characters.');
    }
    if (!_isPasswordRecovery || client.auth.currentSession == null) {
      throw const MillError(
        'This recovery link is invalid or expired. Request a new link.',
      );
    }
    await client.auth.updateUser(UserAttributes(password: newPassword));
    await signOut();
  });
}
