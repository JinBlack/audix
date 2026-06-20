import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores server passwords in the platform secure store
/// (iOS Keychain / Android Keystore-backed EncryptedSharedPreferences).
///
/// Only the password is kept here; the username and other server metadata
/// live in the database. Keys are namespaced by server id.
class CredentialsStore {
  CredentialsStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(int serverId) => 'server_pw_$serverId';

  Future<void> setPassword(int serverId, String password) =>
      _storage.write(key: _key(serverId), value: password);

  Future<String?> getPassword(int serverId) =>
      _storage.read(key: _key(serverId));

  Future<void> deletePassword(int serverId) =>
      _storage.delete(key: _key(serverId));
}
