import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/two_factor_service.dart';

class TwoFactorVerificationScreen extends StatefulWidget {
  final String userId;
  final String method;
  final String? totpSecret;

  const TwoFactorVerificationScreen({
    super.key,
    required this.userId,
    required this.method,
    this.totpSecret,
  });

  @override
  State<TwoFactorVerificationScreen> createState() => _TwoFactorVerificationScreenState();
}

class _TwoFactorVerificationScreenState extends State<TwoFactorVerificationScreen> {
  final _codeController = TextEditingController();
  final _twoFactorService = TwoFactorService();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _sendVerificationCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendVerificationCode() async {
    try {
      if (widget.method == 'email' || widget.method == 'sms') {
        final code = _twoFactorService.generateVerificationCode();
        debugPrint('[2FAScreen] Generated code: $code');

        await _twoFactorService.storeVerificationCode(widget.userId, code, widget.method);

        if (widget.method == 'email') {
          final userDoc = await _firestore.collection('users').doc(widget.userId).get();
          final email = userDoc.data()?['email'] as String?;
          if (email != null) {
            await _twoFactorService.sendEmailVerificationCode(email, code);
            debugPrint('[2FAScreen] Email sent to: $email');
          }
        } else if (widget.method == 'sms') {
          final userDoc = await _firestore.collection('users').doc(widget.userId).get();
          final phone = userDoc.data()?['phone'] as String?;
          if (phone != null) {
            await _twoFactorService.sendSMSVerificationCode(phone, code);
            debugPrint('[2FAScreen] SMS sent to: $phone');
          }
        }
      }
    } catch (e) {
      debugPrint('[2FAScreen] Error sending code: $e');
      setState(() {
        _errorMessage = 'Failed to send verification code. Please try again.';
      });
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();

    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Please enter a 6-digit code';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      bool isValid = false;

      if (widget.method == 'totp' && widget.totpSecret != null) {
        isValid = _twoFactorService.verifyTOTPCode(widget.totpSecret!, code);
      } else {
        isValid = await _twoFactorService.verifyStoredCode(widget.userId, code);
      }

      if (isValid) {
        // Mark session as verified
        await _firestore.collection('twoFactorSessions').doc(widget.userId).update({
          'verified': true,
        });
        debugPrint('[2FAScreen] Verification successful');
        // AuthGate will detect the change and navigate
      } else {
        setState(() {
          _errorMessage = 'Invalid code. Please try again.';
          _isVerifying = false;
        });
      }
    } catch (e) {
      debugPrint('[2FAScreen] Verification error: $e');
      setState(() {
        _errorMessage = 'Verification failed. Please try again.';
        _isVerifying = false;
      });
    }
  }

  Future<void> _cancel() async {
    try {
      await _firestore.collection('twoFactorSessions').doc(widget.userId).delete();
      await _auth.signOut();
    } catch (e) {
      debugPrint('[2FAScreen] Error during cancel: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Two-Factor Authentication'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _cancel,
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.security,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 32),
                Text(
                  widget.method == 'totp'
                      ? 'Enter the code from your authenticator app'
                      : 'A verification code has been sent to your ${widget.method == 'email' ? 'email' : 'phone'}',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    labelText: 'Verification Code',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.pin),
                    errorText: _errorMessage,
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 2),
                  autofocus: true,
                  onSubmitted: (_) => _verify(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isVerifying ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Verify', style: TextStyle(fontSize: 16)),
                  ),
                ),
                if (widget.method != 'totp') ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _sendVerificationCode,
                    child: const Text('Resend Code'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
