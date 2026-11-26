import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/neon_auth_client.dart';

final neonAuthClientProvider = Provider<NeonAuthClient>(
  (ref) => NeonAuthClient(ref.watch(studyDatabaseProvider)),
);

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  NeonAuthClient get _client => ref.read(neonAuthClientProvider);

  @override
  Future<AuthSession?> build() => _client.currentSession();

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _client.signIn(email: email, password: password),
    );
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _client.signUp(name: name, email: email, password: password),
    );
  }

  Future<void> signOut() async {
    await _client.signOut();
    state = const AsyncData(null);
  }
}
