import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class ForgotPasswordPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: Colors.white),
        title: Text(
          'Forgot Password',
          style: TextStyle(color: Color(0xFFE98B38)),
        ),
        backgroundColor: Colors.black,
      ),
      body: Container(
        color: Colors.black,
        child: ForgotPasswordForm(),
      ),
    );
  }
}

class ForgotPasswordForm extends StatefulWidget {
  @override
  _ForgotPasswordFormState createState() => _ForgotPasswordFormState();
}

class _ForgotPasswordFormState extends State<ForgotPasswordForm> {
  TextEditingController emailController = TextEditingController();
  TextEditingController otpController = TextEditingController();
  TextEditingController newPasswordController = TextEditingController();
  bool showOtpWidget = false;
  String? signature;
  final baseUrl = dotenv.env['API_BASE_URL'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Email',
              labelStyle: TextStyle(color: Colors.white),
              filled: true,
              fillColor: Colors.black,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
          ),
          SizedBox(height: 16.0),
          ElevatedButton(
            onPressed: () async {
              String email = emailController.text;
              var response = await sendOtpRequest(email);
              if (response != null && response['signature'] != null) {
                setState(() {
                  showOtpWidget = true;
                  signature = response['signature'];
                });
              } else {
                showError('User does not exist');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              side: BorderSide(
                color: Colors.white,
                width: 1.0,
              ),
            ),
            child: Text('Reset Password'),
          ),
          if (showOtpWidget) otpVerificationWidget(),
        ],
      ),
    );
  }

  Widget otpVerificationWidget() {
    return Column(
      children: [
        TextField(
          controller: otpController,
          decoration: InputDecoration(labelText: 'OTP'),
          keyboardType: TextInputType.text,
        ),
        SizedBox(height: 16.0),
        TextField(
          controller: newPasswordController,
          decoration: InputDecoration(labelText: 'Enter New Password'),
          obscureText: true,
        ),
        SizedBox(height: 16.0),
        ElevatedButton(
          onPressed: () async {
            String otpHashed = hashPassword(otpController.text);
            var verifyResponse = await verifyOtpRequest(emailController.text, otpHashed, signature ?? "");
            if (verifyResponse != null && verifyResponse['signature'] != null) {
              String hashedPassword = hashPassword(newPasswordController.text);
              await sendChangePasswordRequest(emailController.text, hashedPassword, verifyResponse['signature']);
              Navigator.pop(context);
            } else {
              showError(verifyResponse?['message'] ?? 'Invalid OTP');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFFFF9B29),
          ),
          child: Text('Submit'),
        ),
      ],
    );
  }

  Future<Map<String, dynamic>?> sendOtpRequest(String email) async {
      final apiUrl = '$baseUrl/password_otp';
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      return response.statusCode == 200 ? jsonDecode(response.body) : null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> verifyOtpRequest(String email, String otp, String signature) async {
    final fullUrl = '$baseUrl/otp_verification';
    try {
      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp, 'signature': signature}),
      );
      return response.statusCode == 200 ? jsonDecode(response.body) : null;
    } catch (e) {
      return null;
    }
  }

  Future<void> sendChangePasswordRequest(String email, String hashedPassword, String signature) async {
    final fullUrl = '$baseUrl/change_password';
    try {
      await http.post(
        Uri.parse(fullUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': hashedPassword, 'signature': signature}),
      );
    } catch (e) {}
  }

  String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: TextStyle(color: Colors.red))));
  }
}

void main() {
  runApp(MaterialApp(home: ForgotPasswordPage()));
}
