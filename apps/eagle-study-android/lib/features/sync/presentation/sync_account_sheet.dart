import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../application/sync_controller.dart';

Future<void> showSyncAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _SyncAccountSheet(),
  );
}

class _SyncAccountSheet extends ConsumerStatefulWidget {
  const _SyncAccountSheet();

  @override
  ConsumerState<_SyncAccountSheet> createState() => _SyncAccountSheetState();
}

class _SyncAccountSheetState extends ConsumerState<_SyncAccountSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isSignUp = false;
  String? _localError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final name = _nameCtrl.text.trim();
    if (email.isEmpty || password.length < 8) {
      setState(() {
        _localError = 'Enter a valid email and a password (8+ characters).';
      });
      return;
    }
    setState(() => _localError = null);

    final auth = ref.read(authControllerProvider.notifier);
    if (_isSignUp) {
      await auth.signUp(
        name: name.isEmpty ? email.split('@').first : name,
        email: email,
        password: password,
      );
    } else {
      await auth.signIn(email: email, password: password);
    }

    final authState = ref.read(authControllerProvider);
    if (!mounted) return;
    if (authState.hasError) {
      setState(() => _localError = authState.error.toString());
      return;
    }
    if (authState.value != null) {
      await ref.read(syncControllerProvider.notifier).syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final syncState = ref.watch(syncControllerProvider);
    final pendingSync =
        ref.watch(studySummaryProvider).value?.pendingSync ?? 0;
    final session = authState.value;
    final isLoading = authState.isLoading || syncState.syncing;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cloud_sync_rounded,
                  color: AppColors.cyan,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  'Cloud Sync & Account',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              session == null
                  ? 'Sign in with Neon Auth to sync your study sessions to PostgreSQL.'
                  : 'Signed in as ${session.email}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (session != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pendingSync == 0
                          ? 'All sessions synced'
                          : '$pendingSync ${pendingSync == 1 ? 'change' : 'changes'} waiting to upload',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (syncState.lastSyncedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last synced: ${syncState.lastSyncedAt!.toLocal().toString().substring(0, 16)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (syncState.lastError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        syncState.lastError!,
                        style: const TextStyle(
                          color: AppColors.pink,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: isLoading
                    ? null
                    : () => ref.read(syncControllerProvider.notifier).syncNow(),
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(syncState.syncing ? 'Syncing...' : 'Sync Now'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .signOut();
                      },
                child: const Text('Sign Out'),
              ),
            ] else ...[
              if (_isSignUp) ...[
                TextField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => isLoading ? null : _submit(),
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_localError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _localError!,
                  style: const TextStyle(color: AppColors.pink, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isSignUp ? 'Create Account & Sync' : 'Sign In & Sync'),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => setState(() {
                        _isSignUp = !_isSignUp;
                        _localError = null;
                      }),
                child: Text(
                  _isSignUp
                      ? 'Already have an account? Sign in'
                      : 'New here? Create an account',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
