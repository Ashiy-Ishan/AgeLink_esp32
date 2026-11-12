import 'package:flutter/material.dart';
import 'main.dart';

class SignUpScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onSignUp;
  final Function(AuthView) onNavigate;

  const SignUpScreen({super.key, required this.onSignUp, required this.onNavigate});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  static const _blue = Color(0xFF1E88E5);
  static const _darkBlue = Color(0xFF0D47A1);
  static const _text = Color(0xFF26364A);
  static const _muted = Color(0xFF66768A);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Keep the existing registration callback and password validation.
  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match!')),
      );
      return;
    }
    widget.onSignUp({
      'name': _nameController.text,
      'email': _emailController.text,
      'password': _passwordController.text,
    });
  }

  Widget _label(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(label, style: const TextStyle(color: _text, fontSize: 12.5, fontWeight: FontWeight.w700)),
  );

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
      filled: true,
      isDense: true,
      fillColor: const Color(0xFFF7FAFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: border(const Color(0xFFDCE7F5)),
      enabledBorder: border(const Color(0xFFDCE7F5)),
      focusedBorder: border(_blue, 1.5),
      errorBorder: border(Colors.redAccent),
      focusedErrorBorder: border(Colors.redAccent, 1.5),
    );
  }

  Widget _visibilityButton(bool visible, VoidCallback onPressed) => IconButton(
    visualDensity: VisualDensity.compact,
    tooltip: visible ? 'Hide password' : 'Show password',
    icon: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _muted, size: 20),
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Create your account', textAlign: TextAlign.center,
              style: TextStyle(color: _darkBlue, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          const Text('Stay involved in your family’s care.', textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12.5)),
          const SizedBox(height: 10),
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
                _label('Full name'),
                TextFormField(
                  controller: _nameController,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: _decoration('Enter your name', Icons.person_outline_rounded),
                  validator: (v) => v == null || v.isEmpty ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 9),
                _label('Email address'),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: _decoration('Enter your email', Icons.mail_outline_rounded),
                  validator: (v) => v == null || v.isEmpty || !v.contains('@') ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 9),
                _label('Password'),
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: _decoration('At least 6 characters', Icons.lock_outline_rounded,
                      suffix: _visibilityButton(_isPasswordVisible,
                              () => setState(() => _isPasswordVisible = !_isPasswordVisible))),
                  validator: (v) => v == null || v.length < 6 ? 'Password is too short' : null,
                ),
                const SizedBox(height: 9),
                _label('Confirm password'),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: !_isConfirmPasswordVisible,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _decoration('Re-enter password', Icons.verified_user_outlined,
                      suffix: _visibilityButton(_isConfirmPasswordVisible,
                              () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible))),
                  validator: (v) => v != _passwordController.text ? 'Passwords must match' : null,
                ),
                const SizedBox(height: 14),
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
                            'Create Account',
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
          const SizedBox(height: 5),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Already have an account?', style: TextStyle(color: _muted, fontSize: 12.5)),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => widget.onNavigate(AuthView.login),
                child: const Text('Sign in', style: TextStyle(color: _darkBlue, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
