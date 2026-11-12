import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'main.dart';

class LoginScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onLogin;
  final VoidCallback onGoogleSignIn;
  final Function(AuthView) onNavigate;

  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onNavigate,
    required this.onGoogleSignIn,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _isPasswordObscured = true;
  bool _rememberMe = false;

  static const _blue = Color(0xFF1E88E5);
  static const _darkBlue = Color(0xFF0D47A1);
  static const _text = Color(0xFF26364A);
  static const _muted = Color(0xFF66768A);

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Restore only the remembered email, not the password.
  Future<void> _loadRememberedEmail() async {
    final email = await _storage.read(key: 'remembered_email');
    if (!mounted) return;
    if (email != null) {
      setState(() {
        _emailController.text = email;
        _rememberMe = true;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_rememberMe) {
      await _storage.write(key: 'remembered_email', value: _emailController.text);
    } else {
      await _storage.delete(key: 'remembered_email');
    }
    widget.onLogin({
      'email': _emailController.text,
      'password': _passwordController.text,
      'rememberMe': _rememberMe,
    });
  }

  InputDecoration _decoration(String hint, IconData icon, {Widget? suffix}) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _muted, fontSize: 13),
      prefixIcon: Icon(icon, color: _darkBlue, size: 19),
      prefixIconConstraints: const BoxConstraints(minWidth: 42),
      suffixIcon: suffix,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF7FAFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border(const Color(0xFFDCE7F5)),
      enabledBorder: border(const Color(0xFFDCE7F5)),
      focusedBorder: border(_blue, 1.5),
      errorBorder: border(Colors.redAccent),
      focusedErrorBorder: border(Colors.redAccent, 1.5),
    );
  }

  Widget _label(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(label, style: const TextStyle(color: _text, fontSize: 12.5, fontWeight: FontWeight.w700)),
  );

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Welcome back', textAlign: TextAlign.center,
              style: TextStyle(color: _darkBlue, fontSize: 23, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          const Text('Stay connected to the care that matters.', textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE3EDF8)),
              boxShadow: [BoxShadow(color: _darkBlue.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _label('Email address'),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: _decoration('Enter your email', Icons.mail_outline_rounded),
                  validator: (v) => v == null || v.isEmpty || !v.contains('@') ? 'Please enter a valid email' : null,
                ),
                const SizedBox(height: 10),
                _label('Password'),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _isPasswordObscured,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _decoration('Enter your password', Icons.lock_outline_rounded,
                    suffix: IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _isPasswordObscured ? 'Show password' : 'Hide password',
                      icon: Icon(_isPasswordObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: _muted, size: 20),
                      onPressed: () => setState(() => _isPasswordObscured = !_isPasswordObscured),
                    ),
                  ),
                  validator: (v) => v == null || v.length < 6 ? 'Password must be at least 6 characters' : null,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    SizedBox(
                      width: 30,
                      height: 34,
                      child: Checkbox(
                        value: _rememberMe,
                        activeColor: _darkBlue,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) => setState(() => _rememberMe = v ?? false),
                      ),
                    ),
                    const Text('Remember me', style: TextStyle(color: _muted, fontSize: 12)),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 3), visualDensity: VisualDensity.compact),
                      onPressed: () => widget.onNavigate(AuthView.forgotPassword),
                      child: const Text('Forgot password?', style: TextStyle(color: _darkBlue, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_blue, _darkBlue],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: _submit,
                        borderRadius: BorderRadius.circular(12),
                        child: const Center(
                          child: Text(
                            'Sign In',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Divider(
                  color: Color(0xFFDCE7F5),
                  thickness: 1,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'OR',
                  style: TextStyle(
                    color: Color(0xFF66768A),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: Color(0xFFDCE7F5),
                  thickness: 1,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: widget.onGoogleSignIn,
              icon: Image.asset('assets/google_logo.png', width: 18, height: 18,
                  errorBuilder: (_, __, ___) => const Icon(Icons.account_circle_outlined, color: _darkBlue, size: 19)),
              label: const Text('Continue with Google', style: TextStyle(color: _text, fontSize: 13.5, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(backgroundColor: Colors.white, side: const BorderSide(color: Color(0xFFDCE7F5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('New to AgeLink?', style: TextStyle(color: _muted, fontSize: 12.5)),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => widget.onNavigate(AuthView.signup),
                child: const Text('Create account', style: TextStyle(color: _darkBlue, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
