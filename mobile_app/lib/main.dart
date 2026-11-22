import 'package:flutter/material.dart';

import 'app/crm_shell.dart';
import 'core/errors/user_message.dart';
import 'core/theme/app_theme.dart';
import 'data/crm_repo.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/session_storage.dart';

void main() {
  runApp(const BeautyCrmApp());
}

class BeautyCrmApp extends StatefulWidget {
  final String? initialAuthToken;
  final CrmRepo? repoOverride;
  final SessionStorage? sessionStorage;

  const BeautyCrmApp({
    super.key,
    this.initialAuthToken,
    this.repoOverride,
    this.sessionStorage,
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

  late final SessionStorage _storage =
      widget.sessionStorage ?? const SessionStorage();

  late String _accessToken = (widget.initialAuthToken ??
          const String.fromEnvironment('BACKEND_AUTH_TOKEN', defaultValue: ''))
      .trim();
  String _refreshToken = '';
  String _userEmail = '';
  bool _restoringSession = false;
  int _sessionEpoch = 0;
  Future<String?>? _refreshInFlight;

  late final CrmRepo _liveRepo = CrmRepo(
    ApiClient(
      baseUrl: _resolveBackendUrl(),
      tokenProvider: () => _accessToken,
      onUnauthorized: _refreshAccessToken,
    ),
  );

  bool get _isSignedIn => _accessToken.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Nếu không truyền initialAuthToken (chạy app thật), khôi phục phiên đã lưu
    if (widget.initialAuthToken == null && _accessToken.isEmpty) {
      _restoringSession = true;
      _restorePersistedSession();
    }
  }

  Future<void> _restorePersistedSession() async {
    try {
      final saved = await _storage.read();
      if (!mounted) return;
      if (saved == null) {
        setState(() => _restoringSession = false);
        return;
      }

      if (saved.isExpiringSoon && saved.refreshToken.isNotEmpty) {
        try {
          final refreshed = await _authService.refreshSession(
            saved.refreshToken,
            fallbackEmail: saved.email,
          );
          if (!mounted) return;
          if (refreshed != null) {
            await _storage.write(refreshed);
            if (!mounted) return;
            setState(() {
              _accessToken = refreshed.accessToken;
              _refreshToken = refreshed.refreshToken;
              _userEmail = refreshed.email;
              _sessionEpoch += 1;
              _restoringSession = false;
            });
            return;
          }
          // Refresh token đã hết hạn hẳn / bị thu hồi → xóa và về màn đăng nhập
          await _storage.clear();
          if (!mounted) return;
          setState(() => _restoringSession = false);
          return;
        } catch (_) {
          // Mất mạng tạm thời: vẫn giữ phiên đã lưu để app không bị văng ra
        }
      }

      setState(() {
        _accessToken = saved.accessToken;
        _refreshToken = saved.refreshToken;
        _userEmail = saved.email;
        _sessionEpoch += 1;
        _restoringSession = false;
      });
    } catch (_) {
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  Future<String?> _refreshAccessToken() {
    if (_refreshInFlight != null) return _refreshInFlight!;
    final refresh = _refreshToken.trim();
    if (refresh.isEmpty) return Future<String?>.value(null);

    final future = () async {
      try {
        final refreshed = await _authService.refreshSession(
          refresh,
          fallbackEmail: _userEmail,
        );
        if (refreshed == null) {
          await _storage.clear();
          if (mounted) {
            setState(() {
              _accessToken = '';
              _refreshToken = '';
            });
          }
          return null;
        }
        await _storage.write(refreshed);
        if (mounted) {
          setState(() {
            _accessToken = refreshed.accessToken;
            _refreshToken = refreshed.refreshToken;
            _userEmail = refreshed.email;
          });
        }
        return refreshed.accessToken;
      } catch (_) {
        // Lỗi mạng tạm thời: không xóa phiên đang lưu
        return null;
      }
    }();

    _refreshInFlight = future.whenComplete(() => _refreshInFlight = null);
    return _refreshInFlight!;
  }

  Future<void> _onSignedIn(AuthSession session) async {
    await _storage.write(session);
    if (!mounted) return;
    setState(() {
      _accessToken = session.accessToken.trim();
      _refreshToken = session.refreshToken.trim();
      _userEmail = session.email.trim();
      _sessionEpoch += 1;
    });
  }

  Future<void> _onSignOut() async {
    final tokenToRevoke = _accessToken;
    setState(() {
      _accessToken = '';
      _refreshToken = '';
      _userEmail = '';
    });
    await _storage.clear();
    await _authService.signOut(tokenToRevoke);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pyincc AI CRM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: _restoringSession
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _isSignedIn
              ? CrmShell(
                  key: ValueKey<int>(_sessionEpoch),
                  repo: widget.repoOverride ?? _liveRepo,
                  onSignOut: _onSignOut,
                )
              : LoginScreen(
                  authService: _authService,
                  initialEmail: _userEmail,
                  onSignedIn: _onSignedIn,
                ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final String initialEmail;
  final void Function(AuthSession session) onSignedIn;

  const LoginScreen({
    super.key,
    required this.authService,
    this.initialEmail = '',
    required this.onSignedIn,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.initialEmail);
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

  Future<void> _openForgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(initialEmail: _emailCtrl.text),
    );
    if (email == null || email.isEmpty || !mounted) return;

    try {
      await widget.authService.requestPasswordReset(email);
      if (!mounted) return;
      showAppMessage(
        context,
        'Đã gửi liên kết đặt lại mật khẩu tới $email. Vui lòng kiểm tra hộp thư đến hoặc thư rác.',
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, userMessage(error), isError: true);
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
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isLoading ? null : _openForgotPassword,
                        child: const Text('Quên mật khẩu?'),
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

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.initialEmail.trim());
  String? _validationError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _validationError = 'Vui lòng nhập địa chỉ Email hợp lệ.');
      return;
    }
    Navigator.of(context).pop(email);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quên mật khẩu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nhập email tài khoản Chủ tiệm để nhận liên kết đặt lại mật khẩu.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) {
              if (_validationError != null) {
                setState(() => _validationError = null);
              }
            },
            decoration: const InputDecoration(
              labelText: 'Email tài khoản',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          if (_validationError != null) ...[
            const SizedBox(height: 8),
            Text(
              _validationError!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Gửi email'),
        ),
      ],
    );
  }
}
