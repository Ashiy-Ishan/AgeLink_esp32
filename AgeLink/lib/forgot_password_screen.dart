import 'package:flutter/material.dart';
import 'main.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onSendReset;
  final Function(AuthView) onNavigate;

  const ForgotPasswordScreen({
    super.key,
    required this.onSendReset,
    required this.onNavigate,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  static const Color _blue = Color(0xFF1E88E5);
  static const Color _darkBlue = Color(0xFF0D47A1);
  static const Color _text = Color(0xFF26364A);
  static const Color _muted = Color(0xFF66768A);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // The existing parent authentication flow sends the reset email.
  void _submit() {
    if (_formKey.currentState!.validate()) {
      widget.onSendReset({'email': _emailController.text});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              height: 76,
              width: 76,
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.lock_reset_rounded, size: 38, color: _darkBlue),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Reset your password',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              color: _darkBlue,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Enter your account email address and we'll send you a password reset link.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _muted, height: 1.5),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE3EDF8)),
              boxShadow: [
                BoxShadow(
                  color: _darkBlue.withValues(alpha: 0.05),
                  blurRadius: 22,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Email address',
                  style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 9),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Enter your email',
                    hintStyle: const TextStyle(color: _muted, fontSize: 14),
                    prefixIcon: const Icon(Icons.mail_outline_rounded, color: _darkBlue),
                    filled: true,
                    fillColor: const Color(0xFFF7FAFF),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFDCE7F5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFDCE7F5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _blue, width: 1.6),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.redAccent),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty || !value.contains('@')
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_blue, _darkBlue],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Send Reset Link',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: TextButton.icon(
              onPressed: () => widget.onNavigate(AuthView.login),
              icon: const Icon(Icons.arrow_back_rounded, color: _darkBlue, size: 19),
              label: const Text(
                'Back to Sign In',
                style: TextStyle(color: _darkBlue, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
