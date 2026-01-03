// ignore_for_file: depend_on_referenced_packages

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CustomEmailService {
  // SendGrid API configuration
  static const String _sendGridApiKey = '76MVEVSK2METP4TSSJGHBVU5';
  static const String _fromEmail = 'noreply@yourdomain.com'; // Replace with your verified domain
  static const String _fromName = 'MoneyMint';
  
  static Future<void> sendCustomPasswordResetEmail(String email) async {
    try {
      // 1. Generate password reset link
      final auth = FirebaseAuth.instance;
      final actionCodeSettings = ActionCodeSettings(
        url: 'https://money--mint.firebaseapp.com/__/auth/action',
        handleCodeInApp: false,
        iOSBundleId: 'com.example.money_mint',
        androidPackageName: 'com.example.money_mint',
        androidInstallApp: true,
        androidMinimumVersion: '1',
      );
      
      // For now, fall back to Firebase if SendGrid is not configured
      if (_sendGridApiKey == 'YOUR_SENDGRID_API_KEY') {
        await auth.sendPasswordResetEmail(
          email: email,
          actionCodeSettings: actionCodeSettings,
        );
        return;
      }
      
      // 2. Send via SendGrid with custom template
      final resetLink = await _generateResetLink(email, actionCodeSettings);
      await _sendEmailViaSendGrid(email, resetLink);
      
    } catch (e) {
      throw Exception('Failed to send password reset email: $e');
    }
  }
  
  static Future<String> _generateResetLink(String email, ActionCodeSettings actionCodeSettings) async {
    // For now, we'll use Firebase's default reset link format
    // In a production environment, you'd want to generate this properly
    return 'https://money--mint.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=generated_code&email=${Uri.encodeComponent(email)}';
  }
  
  static Future<void> _sendEmailViaSendGrid(String email, String resetLink) async {
    final url = Uri.parse('https://api.sendgrid.com/v3/mail/send');
    
    final emailBody = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reset Your MoneyMint Password</title>
</head>
<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
    <div style="text-align: center; margin-bottom: 30px;">
        <img src="https://money--mint.firebaseapp.com/assets/images/app_logo.png" 
             alt="MoneyMint Logo" 
             style="width: 120px; height: 120px; margin-bottom: 10px;">
        <h2 style="color: #274647; margin: 10px 0;">MoneyMint</h2>
    </div>
    
    <h3 style="color: #274647;">Reset Your Password</h3>
    
    <p>Hello,</p>
    
    <p>We received a request to reset your password for your MoneyMint account. Click the button below to reset your password:</p>
    
    <div style="text-align: center; margin: 30px 0;">
        <a href="$resetLink" 
           style="background-color: #274647; color: white; padding: 15px 30px; text-decoration: none; border-radius: 8px; display: inline-block; font-weight: bold;">
            Reset Password
        </a>
    </div>
    
    <p style="font-size: 14px; color: #666;">
        If the button above doesn't work, you can copy and paste this link into your browser:<br>
        <a href="$resetLink" style="color: #274647;">$resetLink</a>
    </p>
    
    <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee; font-size: 12px; color: #888;">
        <p><strong>Security Notice:</strong></p>
        <ul style="color: #888;">
            <li>This link will expire in 24 hours for your security</li>
            <li>If you didn't request this password reset, please ignore this email</li>
            <li>Never share this link with anyone</li>
        </ul>
        
        <p style="margin-top: 20px;">
            Best regards,<br>
            The MoneyMint Team
        </p>
    </div>
</body>
</html>
    ''';
    
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $_sendGridApiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'personalizations': [{
          'to': [{'email': email}],
          'subject': 'Reset Your MoneyMint Password'
        }],
        'from': {
          'email': _fromEmail,
          'name': _fromName
        },
        'reply_to': {'email': _fromEmail},
        'content': [{
          'type': 'text/html',
          'value': emailBody
        }]
      }),
    );
    
    if (response.statusCode != 202) {
      throw Exception('SendGrid API error: ${response.statusCode} - ${response.body}');
    }
  }
}
