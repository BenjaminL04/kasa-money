import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/digests/sha256.dart';
import 'logged_in_home.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SplitBillPage extends StatefulWidget {
  @override
  _SplitBillPageState createState() => _SplitBillPageState();
}

class _SplitBillPageState extends State<SplitBillPage> {
  final usernameController = TextEditingController();
  final amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final baseUrl = dotenv.env['API_BASE_URL'];

  // ZARP Balance State
  bool isLoadingBalance = true;
  String zarpBalance = '0.00';

  SecureRandom getSecureRandom() {
    final secureRandom = SecureRandom('Fortuna')
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => Random.secure().nextInt(256)))));
    return secureRandom;
  }

  Uint8List bigIntToBytes(BigInt number, int byteLength) {
    final byteList = number.toRadixString(16).padLeft(byteLength * 2, '0');
    return Uint8List.fromList(List.generate(byteLength, (i) {
      return int.parse(byteList.substring(i * 2, i * 2 + 2), radix: 16);
    }));
  }

  @override
  void initState() {
    super.initState();
    _fetchZarpBalance();
  }

  Future<void> _fetchZarpBalance() async {
    setState(() {
      isLoadingBalance = true;
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (privateKeyBase64 == null || token == null) {
      setState(() {
        isLoadingBalance = false;
      });
      return;
    }

    final nonce = List<int>.generate(16, (i) => Random.secure().nextInt(256));
    String nonceBase64 = base64Encode(nonce);

    String messageWithNonce = "$token:$nonceBase64";
    final messageHash = SHA256Digest().process(utf8.encode(messageWithNonce));

    Uint8List privateKeyBytes = base64Decode(privateKeyBase64);
    BigInt privateKeyInt = BigInt.parse(privateKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(), radix: 16);

    final privateKey = ECPrivateKey(privateKeyInt, ECDomainParameters('secp256r1'));
    final secureRandom = getSecureRandom();

    final signer = Signer('SHA-256/ECDSA')
      ..init(true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(privateKey), secureRandom));

    ECSignature signature = signer.generateSignature(Uint8List.fromList(messageHash)) as ECSignature;
    String signatureBase64 = base64Encode(
      bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32),
    );

    final fullUrl = '$baseUrl/check_balance';

    try {
      final response = await http.post(
        Uri.parse(fullUrl),
        body: {
          'token': token,
          'nonce': nonceBase64,
          'signature': signatureBase64,
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final double zarpValue = double.parse(data['zarp_balance'].toString());

        setState(() {
          zarpBalance = zarpValue.toStringAsFixed(2);
          isLoadingBalance = false;
        });
      } else {
        setState(() {
          zarpBalance = 'Error';
          isLoadingBalance = false;
        });
      }
    } catch (e) {
      setState(() {
        zarpBalance = 'Error';
        isLoadingBalance = false;
      });
    }
  }

  Future<void> splitBill(String username) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (privateKeyBase64 == null || token == null) {
      _showSnackBar('Error: Missing authentication', isError: true);
      return;
    }

    final nonce = List<int>.generate(16, (i) => Random.secure().nextInt(256));
    String nonceBase64 = base64Encode(nonce);
    String messageWithNonce = "$token:$nonceBase64";
    final messageHash = SHA256Digest().process(utf8.encode(messageWithNonce));

    Uint8List privateKeyBytes = base64Decode(privateKeyBase64);
    BigInt privateKeyInt = BigInt.parse(privateKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
    final privateKey = ECPrivateKey(privateKeyInt, ECDomainParameters('secp256r1'));
    final secureRandom = getSecureRandom();
    final signer = Signer('SHA-256/ECDSA')
      ..init(true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(privateKey), secureRandom));

    ECSignature signature = signer.generateSignature(Uint8List.fromList(messageHash)) as ECSignature;
    String signatureBase64 = base64Encode(
      bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32),
    );

    final fullUrl = '$baseUrl/send_zarp';

    final response = await http.post(
      Uri.parse(fullUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'currency': "zarp",
        'token': token,
        'nonce': nonceBase64,
        'signature': signatureBase64,
        'receiver_phone_number': username,
        'amount': double.parse(amountController.text),
        'type': 'split',
        'sender_reference': 'split',
        'receiver_reference': 'split',
      }),
    );

    final responseData = jsonDecode(response.body);
    if (responseData['message'] == 'payment_complete') {
      _showSnackBar('Bill split successfully!', isError: false);
      await _fetchZarpBalance(); // Refresh balance
      Navigator.pop(context);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoggedInHomePage()),
      );
    } else {
      final error = responseData['error'] ?? 'Unknown error';
      _showSnackBar('Error: $error', isError: true);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Color(0xFFFF9B29),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void showSplitConfirmationDialog(String username) {
    final String amountText = amountController.text.trim();
    final double? amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      _showSnackBar('Please enter a valid amount', isError: true);
      return;
    }

    final double currentBalance = double.tryParse(zarpBalance) ?? 0.0;

    if (amount > currentBalance) {
      _showSnackBar('Insufficient ZARP balance', isError: true);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Split',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Split bill with @$username',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Amount: $amount ZARP',
              style: TextStyle(color: Color(0xFFFF9B29), fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Reference: split',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              splitBill(username);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF9B29),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Split Now'),
          ),
        ],
      ),
    );
  }

  void showAmountDialog(String username) {
    amountController.clear(); // Reset amount
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enter Split Amount', style: TextStyle(color: Colors.white)),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: amountController,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Amount (ZARP)',
              labelStyle: TextStyle(color: Colors.white),
              prefixText: 'Z ',
              prefixStyle: TextStyle(color: Colors.white),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF9B29), width: 2)),
            ),
            validator: (value) {
              if (value?.isEmpty ?? true) return 'Enter amount';
              final num = double.tryParse(value!);
              if (num == null || num <= 0) return 'Enter valid amount';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context);
                showSplitConfirmationDialog(username);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF9B29),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Review Split'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Split Bill', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // === ZARP BALANCE AT TOP ===
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color(0xFFFF9B29), width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    'Your ZARP Balance',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  SizedBox(height: 4),
                  isLoadingBalance
                      ? SizedBox(
                          height: 36,
                          child: LinearProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9B29)),
                            backgroundColor: Colors.grey[800],
                          ),
                        )
                      : Text(
                          '$zarpBalance ZARP',
                          style: TextStyle(
                            fontSize: 32,
                            color: Color(0xFFFF9B29),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ],
              ),
            ),
            SizedBox(height: 30),

            // Username Field
            TextFormField(
              controller: usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: 'e.g., johndoe',
                labelStyle: TextStyle(color: Colors.white),
                hintStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.alternate_email, color: Colors.white),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF9B29), width: 2)),
              ),
              style: TextStyle(color: Colors.white),
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              onChanged: (value) {
                if (value != value.toLowerCase()) {
                  usernameController.value = TextEditingValue(
                    text: value.toLowerCase(),
                    selection: usernameController.selection,
                  );
                }
              },
            ),
            SizedBox(height: 30),

            // Next Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final username = usernameController.text.trim();
                  if (username.isEmpty) {
                    _showSnackBar('Please enter a username', isError: true);
                    return;
                  }
                  if (!RegExp(r'^[a-z0-9_-]{3,30}$').hasMatch(username)) {
                    _showSnackBar('Invalid username format', isError: true);
                    return;
                  }
                  showAmountDialog(username);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFFF9B29),
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 3,
                ),
                child: Text(
                  'Next',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    usernameController.dispose();
    amountController.dispose();
    super.dispose();
  }
}