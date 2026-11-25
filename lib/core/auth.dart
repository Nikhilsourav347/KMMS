import 'domain.dart';

class MillError implements Exception {
  const MillError(this.message);
  final String message;
}

class EmailVerificationRequired extends MillError {
  const EmailVerificationRequired()
    : super('Verify your email address before signing in.');
}

class AccountSetup {
  const AccountSetup(this.name, this.email, this.password);
  final String name;
  final String email;
  final String password;
}

enum AuthFlow { signedOut }

abstract interface class MillAuth {
  Staff? get currentStaff;
  bool get isPasswordRecovery;
  String? get recoveryError;
  Stream<AuthFlow> get stateChanges;
  Future<Staff?> restore();
  Future<Staff> signIn(String email, String password, {StaffRole? role});
  Future<void> signOut();
  Future<RowData> profile();
  Future<void> editProfile(String name, String email, String phone);
  Future<void> changePassword(String currentPassword, String newPassword);
  Future<bool> addAccount(
    StaffRole role,
    AccountSetup account, {
    String phone = '',
  });
  Future<List<RowData>> managers();
  Future<void> setManagerEnabled(String email, bool enabled);
  Future<void> requestRecovery(String email);
  Future<void> requestEmailVerification(String email);
  Future<void> recoverWithCode(String email, String code, String password);
  Future<void> completeRecovery(String newPassword);
}

String friendlyError(Object error) => error is MillError
    ? error.message
    : 'The request could not be completed. Check your connection and try again.';

String normalizedEmail(String email) => email.trim().toLowerCase();

bool validEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
