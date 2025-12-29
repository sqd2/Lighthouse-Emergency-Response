import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/two_factor_service.dart';

class TwoFactorSettingsScreen extends StatefulWidget {
  const TwoFactorSettingsScreen({super.key});

  @override
  State<TwoFactorSettingsScreen> createState() => _TwoFactorSettingsScreenState();
}

class _TwoFactorSettingsScreenState extends State<TwoFactorSettingsScreen> {
  final _twoFactorService = TwoFactorService();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _twoFactorEnabled = false;
  String _twoFactorMethod = 'none';
  String? _totpSecret;

  String? _userEmail;
  String? _userPhone;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Get user data
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null) {
          setState(() {
            _userEmail = data['email'] as String?;
            _userPhone = data['phone'] as String?;
            _twoFactorEnabled = data['twoFactorEnabled'] ?? false;
            _twoFactorMethod = data['twoFactorMethod'] ?? 'none';
            _totpSecret = data['totpSecret'] as String?;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _enable2FA(String method) async {
    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      String? totpSecret;
      bool verified = false;

      if (method == 'totp') {
        // Generate TOTP secret and show QR code for setup
        totpSecret = _twoFactorService.generateTOTPSecret();
        verified = await _showTOTPSetupDialog(totpSecret);
      } else if (method == 'email') {
        // Send verification code to email and verify
        if (_userEmail == null) {
          throw Exception('Email not found. Please update your profile.');
        }
        verified = await _sendAndVerifyCode('email', _userEmail!);
      } else if (method == 'sms') {
        // Send verification code to phone and verify
        if (_userPhone == null) {
          throw Exception('Phone number not found. Please update your profile.');
        }
        verified = await _sendAndVerifyCode('sms', _userPhone!);
      }

      if (verified) {
        await _twoFactorService.enable2FA(user.uid, method, totpSecret: totpSecret);

        if (mounted) {
          setState(() {
            _twoFactorEnabled = true;
            _twoFactorMethod = method;
            _totpSecret = totpSecret;
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Two-factor authentication enabled successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to enable 2FA: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disable2FA() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Two-Factor Authentication'),
        content: const Text(
          'Are you sure you want to disable two-factor authentication? This will make your account less secure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Disable', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await _twoFactorService.disable2FA(user.uid);

      if (mounted) {
        setState(() {
          _twoFactorEnabled = false;
          _twoFactorMethod = 'none';
          _totpSecret = null;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Two-factor authentication disabled'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to disable 2FA: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _showTOTPSetupDialog(String secret) async {
    final email = _userEmail ?? 'user@example.com'; // Fallback if email is null
    final otpAuthURL = _twoFactorService.generateOTPAuthURL(email, secret);
    final codeController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Setup Authenticator App'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scan this QR code with your authenticator app (Google Authenticator, Authy, etc.):',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: otpAuthURL,
                  version: QrVersions.auto,
                  size: 200,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Or enter this secret key manually:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              SelectableText(
                secret,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Text('Enter the 6-digit code from your app to verify:'),
              const SizedBox(height: 8),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Verification Code',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.pin),
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
            ],
          ),
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

              final isValid = _twoFactorService.verifyTOTPCode(secret, code);
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

  Future<bool> _sendAndVerifyCode(String method, String destination) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Generate and send code
      final code = _twoFactorService.generateVerificationCode();
      await _twoFactorService.storeVerificationCode(user.uid, code, method);

      if (method == 'email') {
        await _twoFactorService.sendEmailVerificationCode(destination, code);
      } else if (method == 'sms') {
        await _twoFactorService.sendSMSVerificationCode(destination, code);
      }

      if (!mounted) return false;

      // Show verification dialog
      final codeController = TextEditingController();
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Verify ${method == 'email' ? 'Email' : 'Phone Number'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'A 6-digit verification code has been sent to ${method == 'email' ? 'your email' : 'your phone'}.',
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
                final enteredCode = codeController.text.trim();
                if (enteredCode.length != 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a 6-digit code'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final isValid = await _twoFactorService.verifyStoredCode(user.uid, enteredCode);
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send verification code: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Two-Factor Authentication'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _twoFactorEnabled ? Icons.verified_user : Icons.security,
                                color: _twoFactorEnabled ? Colors.green : Colors.grey,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _twoFactorEnabled ? '2FA Enabled' : '2FA Disabled',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (_twoFactorEnabled)
                                      Text(
                                        'Method: ${_get2FAMethodName(_twoFactorMethod)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _twoFactorEnabled
                                ? 'Your account is protected with two-factor authentication.'
                                : 'Enable two-factor authentication to add an extra layer of security to your account.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Enable/Disable button
                  if (_twoFactorEnabled) ...[
                    ElevatedButton.icon(
                      onPressed: _disable2FA,
                      icon: const Icon(Icons.security, color: Colors.white),
                      label: const Text('Disable 2FA', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Choose a verification method:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // Email option
                    if (_userEmail != null)
                      _buildMethodCard(
                        icon: Icons.email,
                        title: 'Email Verification',
                        description: 'Receive a code via email: ${_maskEmail(_userEmail!)}',
                        color: Colors.blue,
                        onTap: () => _enable2FA('email'),
                      ),

                    const SizedBox(height: 12),

                    // SMS option
                    if (_userPhone != null)
                      _buildMethodCard(
                        icon: Icons.sms,
                        title: 'SMS Verification',
                        description: 'Receive a code via SMS: ${_maskPhone(_userPhone!)}',
                        color: Colors.green,
                        onTap: () => _enable2FA('sms'),
                      ),

                    const SizedBox(height: 12),

                    // Authenticator app option
                    _buildMethodCard(
                      icon: Icons.qr_code,
                      title: 'Authenticator App',
                      description: 'Use Google Authenticator, Authy, or similar apps',
                      color: Colors.orange,
                      onTap: () => _enable2FA('totp'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildMethodCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _get2FAMethodName(String method) {
    switch (method) {
      case 'email':
        return 'Email';
      case 'sms':
        return 'SMS';
      case 'totp':
        return 'Authenticator App';
      default:
        return 'None';
    }
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final username = parts[0];
    final domain = parts[1];
    if (username.length <= 2) return email;
    return '${username.substring(0, 2)}***@$domain';
  }

  String _maskPhone(String phone) {
    if (phone.length <= 6) return phone;
    return '${phone.substring(0, 6)}***';
  }
}
