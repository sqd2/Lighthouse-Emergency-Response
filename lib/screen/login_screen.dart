import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/validators.dart';
import '../services/two_factor_service.dart';

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
        debugPrint('[2FA] Starting login process');

        // Sign in with Firebase Auth first
        final userCred = await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        final userId = userCred.user?.uid;
        if (userId == null) {
          debugPrint('[2FA] ERROR: userId is null after sign-in');
          throw Exception('Authentication failed - no user ID');
        }

        debugPrint('[2FA] User signed in: $userId');

        try {
          // IMMEDIATELY create session document to prevent race condition
          await _firestore.collection('twoFactorSessions').doc(userId).set({
            'verified': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          debugPrint('[2FA] Session created immediately after sign-in');
        } catch (e) {
          debugPrint('[2FA] ERROR creating session: $e');
          // If session creation fails, sign out and show error
          await _auth.signOut();
          throw Exception('Failed to create 2FA session: $e');
        }

        // Now check if 2FA is enabled
        final twoFactorSettings = await _twoFactorService.get2FASettings(userId);
        debugPrint('[2FA] Settings: $twoFactorSettings');

        if (twoFactorSettings != null && twoFactorSettings['twoFactorEnabled'] == true) {
          debugPrint('[2FA] 2FA is enabled');

          final twoFactorMethod = twoFactorSettings['twoFactorMethod'] as String?;
          if (twoFactorMethod == null || twoFactorMethod == 'none') {
            // 2FA misconfigured - clean up and exit
            try {
              await _firestore.collection('twoFactorSessions').doc(userId).delete();
            } catch (e) {
              debugPrint('[2FA] Error deleting session: $e');
            }
            await _auth.signOut();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('2FA configuration error. Please contact support.'),
                backgroundColor: Colors.red,
              ),
            );
            setState(() => _isLoading = false);
            return;
          }

          // Session already created - AuthGate will show verification screen
          debugPrint('[2FA] Session created, AuthGate will handle verification');
          // Don't stop loading - let AuthGate transition to verification screen
        } else {
          // No 2FA enabled - mark session as verified and proceed
          debugPrint('[2FA] No 2FA enabled, marking session verified');
          try {
            await _firestore.collection('twoFactorSessions').doc(userId).update({
              'verified': true,
            });
          } catch (e) {
            debugPrint('[2FA] ERROR updating session: $e');
            // Try set instead of update
            await _firestore.collection('twoFactorSessions').doc(userId).set({
              'verified': true,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
        // AuthGate will handle navigation
        // Don't set loading to false here - let AuthGate navigate
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

        final newUserId = userCred.user?.uid;
        if (newUserId == null) {
          throw Exception('Registration failed - no user ID');
        }

        await _firestore.collection('users').doc(newUserId).set({
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'role': _selectedRole,
          'createdAt': Timestamp.now(),
          'emailVerified': false,
          'twoFactorEnabled': false,
        });

        // Send email verification
        final user = userCred.user;
        if (user != null) {
          await user.sendEmailVerification();
        }

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
      debugPrint('[2FA] FirebaseAuthException: ${e.code} - ${e.message}');
      if (!mounted) return;
      final errorMessage = Validators.getFirebaseAuthErrorMessage(e.code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      setState(() => _isLoading = false);
    } catch (e, stack) {
      debugPrint('[2FA] Unexpected error: $e');
      debugPrint('[2FA] Stack trace: $stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      setState(() => _isLoading = false);
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
      debugPrint('[2FA] _verify2FA called with method: $method, userId: $userId');
      debugPrint('[2FA] mounted: $mounted');

      if (method == 'totp' && totpSecret != null) {
        // TOTP verification - show dialog to enter code
        debugPrint('[2FA] Showing TOTP dialog');
        return await _showTOTPVerificationDialog(totpSecret);
      } else if (method == 'email' || method == 'sms') {
        // Generate and store verification code
        debugPrint('[2FA] Generating verification code for $method');
        final code = _twoFactorService.generateVerificationCode();
        debugPrint('[2FA] Generated code: $code');

        await _twoFactorService.storeVerificationCode(userId, code, method);
        debugPrint('[2FA] Code stored in Firestore');

        // Send email/SMS in background (don't wait for it)
        // This prevents blocking the dialog from showing
        if (method == 'email') {
          _firestore.collection('users').doc(userId).get().then((userDoc) {
            final email = userDoc.data()?['email'] as String?;
            debugPrint('[2FA] Sending email to: $email');
            if (email != null) {
              _twoFactorService.sendEmailVerificationCode(email, code).then((_) {
                debugPrint('[2FA] Email sent successfully');
              }).catchError((e) {
                debugPrint('[2FA] ERROR sending email: $e');
              });
            } else {
              debugPrint('[2FA] ERROR: Email is null!');
            }
          });
        } else if (method == 'sms') {
          _firestore.collection('users').doc(userId).get().then((userDoc) {
            final phone = userDoc.data()?['phone'] as String?;
            debugPrint('[2FA] Sending SMS to: $phone');
            if (phone != null) {
              _twoFactorService.sendSMSVerificationCode(phone, code).then((_) {
                debugPrint('[2FA] SMS sent successfully');
              }).catchError((e) {
                debugPrint('[2FA] ERROR sending SMS: $e');
              });
            } else {
              debugPrint('[2FA] ERROR: Phone is null!');
            }
          });
        }

        // Show dialog immediately (don't wait for email/SMS to send)
        debugPrint('[2FA] Showing dialog immediately');
        if (!mounted) {
          debugPrint('[2FA] ERROR: Widget is not mounted, cannot show dialog!');
          return false;
        }

        final result = await _showCodeVerificationDialog(userId, method);
        debugPrint('[2FA] Dialog result: $result');
        return result;
      }
      debugPrint('[2FA] No matching method, returning false');
      return false;
    } catch (e, stack) {
      debugPrint('[2FA] Error in _verify2FA: $e');
      debugPrint('[2FA] Stack trace: $stack');
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
                    Icons.emergency,
                    size: 64,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Lighthouse',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Emergency Response System',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
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
