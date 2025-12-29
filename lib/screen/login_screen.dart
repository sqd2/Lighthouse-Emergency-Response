import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/validators.dart';
import '../services/two_factor_service.dart';
import '../services/two_factor_gate.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  final _twoFactorService = TwoFactorService();

  bool _isLogin = true;
  bool _isLoading = false;
  String _selectedRole = 'citizen';
  bool _obscurePassword = true;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<bool> _checkEmailExists(String email) async {
    try {
      // Check if email exists in Firestore users collection
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        // Login user
        final userCred = await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // Check if 2FA is enabled
        final userId = userCred.user!.uid;
        final twoFactorSettings = await _twoFactorService.get2FASettings(userId);
        if (twoFactorSettings != null && twoFactorSettings['twoFactorEnabled'] == true) {
          // Get 2FA method and validate it's not null
          final twoFactorMethod = twoFactorSettings['twoFactorMethod'] as String?;
          if (twoFactorMethod == null || twoFactorMethod == 'none') {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('2FA configuration error. Please reconfigure 2FA in settings.'),
                backgroundColor: Colors.red,
              ),
            );
            setState(() => _isLoading = false);
            // Sign out since 2FA is misconfigured
            await _auth.signOut();
            return;
          }

          // Set 2FA pending flag to block navigation
          TwoFactorGate.setVerifying(true);
          setState(() => _isLoading = false);

          // Verify 2FA
          final verified = await _verify2FA(
            userId,
            twoFactorMethod,
            twoFactorSettings['totpSecret'] as String?,
          );

          // Clear 2FA pending flag
          TwoFactorGate.setVerifying(false);

          if (verified) {
            // 2FA verified - user is already signed in, AuthGate will handle navigation
            if (!mounted) return;
            // Trigger auth state refresh to allow navigation
            setState(() => _isLoading = false);
          } else {
            // 2FA failed - sign out the user
            await _auth.signOut();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('2FA verification failed or cancelled'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
        // If no 2FA, login is complete - AuthGate handles navigation
      } else {
        // Check if email already exists
        final emailExists = await _checkEmailExists(_emailController.text.trim());
        if (emailExists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('An account with this email already exists. Please login instead.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isLoading = false);
          return;
        }

        // Register user
        final userCred = await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        await _firestore.collection('users').doc(userCred.user!.uid).set({
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'role': _selectedRole,
          'createdAt': Timestamp.now(),
          'emailVerified': false,
          'twoFactorEnabled': false,
        });

        // Send email verification
        await userCred.user!.sendEmailVerification();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Please check your email to verify your account.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      }
      //  IMPORTANT: No navigation here. AuthGate in main.dart handles navigation.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final errorMessage = Validators.getFirebaseAuthErrorMessage(e.code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email address and we\'ll send you a link to reset your password.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: Validators.validateEmail,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              final validationError = Validators.validateEmail(email);

              if (validationError != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(validationError), backgroundColor: Colors.red),
                );
                return;
              }

              try {
                await _auth.sendPasswordResetEmail(email: email);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password reset email sent! Please check your inbox.'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 5),
                  ),
                );
              } on FirebaseAuthException catch (e) {
                final errorMessage = Validators.getFirebaseAuthErrorMessage(e.code);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorMessage),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );
  }

  Future<bool> _verify2FA(String userId, String method, String? totpSecret) async {
    try {
      if (method == 'totp' && totpSecret != null) {
        // TOTP verification - show dialog to enter code
        return await _showTOTPVerificationDialog(totpSecret);
      } else if (method == 'email' || method == 'sms') {
        // Send verification code and show dialog
        final code = _twoFactorService.generateVerificationCode();
        await _twoFactorService.storeVerificationCode(userId, code, method);

        if (method == 'email') {
          final userDoc = await _firestore.collection('users').doc(userId).get();
          final email = userDoc.data()?['email'] as String?;
          if (email != null) {
            await _twoFactorService.sendEmailVerificationCode(email, code);
          }
        } else if (method == 'sms') {
          final userDoc = await _firestore.collection('users').doc(userId).get();
          final phone = userDoc.data()?['phone'] as String?;
          if (phone != null) {
            await _twoFactorService.sendSMSVerificationCode(phone, code);
          }
        }

        return await _showCodeVerificationDialog(userId, method);
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('2FA verification error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _showTOTPVerificationDialog(String totpSecret) async {
    final codeController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Two-Factor Authentication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.security, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Enter the 6-digit code from your authenticator app:',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Verification Code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.pin),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final code = codeController.text.trim();
              if (code.length != 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a 6-digit code'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final isValid = _twoFactorService.verifyTOTPCode(totpSecret, code);
              if (isValid) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid code. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    codeController.dispose();
    return result ?? false;
  }

  Future<bool> _showCodeVerificationDialog(String userId, String method) async {
    final codeController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Two-Factor Authentication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.security, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            Text(
              'A verification code has been sent to your ${method == 'email' ? 'email' : 'phone'}.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Verification Code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.pin),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.length != 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a 6-digit code'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final isValid = await _twoFactorService.verifyStoredCode(userId, code);
              if (isValid) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid or expired code. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    codeController.dispose();
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Login' : 'Register'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo/Title
                  Icon(
                    Icons.security,
                    size: 80,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lighthouse Emergency',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Registration fields
                  if (!_isLogin) ...[
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: Validators.validateName,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        hintText: '+60123456789',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: Validators.validatePhoneNumber,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Register as',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'citizen', child: Text('Citizen')),
                        DropdownMenuItem(value: 'dispatcher', child: Text('Dispatcher')),
                      ],
                      onChanged: (value) => setState(() => _selectedRole = value!),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.validateEmail,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: _isLogin ? null : Validators.validatePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                  ),

                  // Password requirements hint (for registration only)
                  if (!_isLogin) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Password must be at least 8 characters with uppercase, lowercase, number, and special character',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],

                  // Forgot password (login only)
                  if (_isLogin) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showForgotPasswordDialog,
                        child: const Text('Forgot Password?'),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Submit button
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            _isLogin ? 'Login' : 'Register',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),

                  const SizedBox(height: 16),

                  // Toggle login/register
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                        _formKey.currentState?.reset();
                      });
                    },
                    child: Text(
                      _isLogin
                          ? 'Don\'t have an account? Register'
                          : 'Already have an account? Login',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
