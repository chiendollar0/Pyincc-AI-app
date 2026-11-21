import 'package:flutter/material.dart';

import 'app/crm_shell.dart';
import 'core/errors/user_message.dart';
import 'core/theme/app_theme.dart';
import 'data/crm_repo.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';

void main() {
  runApp(const BeautyCrmApp());
}

class BeautyCrmApp extends StatefulWidget {
  final String? initialAuthToken;
  final CrmRepo? repoOverride;

  const BeautyCrmApp({
    super.key,
    this.initialAuthToken,
    this.repoOverride,
  });

  @override
  State<BeautyCrmApp> createState() => _BeautyCrmAppState();
}

class _BeautyCrmAppState extends State<BeautyCrmApp> {
  static const String _defaultBackendUrl = 'https://pyincccrm.bothelper.vn';
  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ihufvqrxdswgbagzhydb.supabase.co',
  );
  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const String _tryOnApiUrl = String.fromEnvironment(
    'TRYON_API_URL',
    defaultValue: '',
  );
  static const String _webhookApiUrl = String.fromEnvironment(
    'WEBHOOK_API_URL',
    defaultValue: '',
  );
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String _resolveBackendUrl() {
    for (final raw in const [_tryOnApiUrl, _webhookApiUrl, _apiBaseUrl]) {
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return _defaultBackendUrl;
  }

  final AuthService _authService = const AuthService(
    supabaseUrl: _supabaseUrl,
    supabaseAnonKey: _supabaseAnonKey,
  );

  late String _accessToken = (widget.initialAuthToken ??
          const String.fromEnvironment('BACKEND_AUTH_TOKEN', defaultValue: ''))
      .trim();

  bool get _isSignedIn => _accessToken.isNotEmpty;

  CrmRepo _buildRepo() =>
      widget.repoOverride ??
      CrmRepo(
        ApiClient(
          baseUrl: _resolveBackendUrl(),
          authToken: _accessToken,
        ),
      );

  void _onSignedIn(AuthSession session) {
    setState(() {
      _accessToken = session.accessToken.trim();
    });
  }

  Future<void> _onSignOut() async {
    final tokenToRevoke = _accessToken;
    setState(() {
      _accessToken = '';
    });
    await _authService.signOut(tokenToRevoke);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pyincc AI CRM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: _isSignedIn
          ? CrmShell(
              key: ValueKey<String>(_accessToken),
              repo: _buildRepo(),
              onSignOut: _onSignOut,
            )
          : LoginScreen(
              authService: _authService,
              onSignedIn: _onSignedIn,
            ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final void Function(AuthSession session) onSignedIn;

  const LoginScreen({
    super.key,
    required this.authService,
    required this.onSignedIn,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorText;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final session = await widget.authService.signInWithPassword(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      widget.onSignedIn(session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorText = userMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/brand/hero.png',
                            width: 112,
                            height: 112,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.spa_outlined,
                              size: 56,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Pyincc AI CRM',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Đăng nhập bằng tài khoản Chủ tiệm đã được cấp quyền.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email đăng nhập',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _isLoading ? null : _submitLogin(),
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Hiện mật khẩu'
                                : 'Ẩn mật khẩu',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorText!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _submitLogin,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(
                          _isLoading ? 'Đang đăng nhập...' : 'Đăng nhập',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
