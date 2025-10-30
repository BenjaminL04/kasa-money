import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/digests/sha256.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const String authTokenKey = 'auth_token';
const String private = 'private_key';

class TipPage extends StatefulWidget {
  @override
  _TipPageState createState() => _TipPageState();
}

class _TipPageState extends State<TipPage> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _recipientController = TextEditingController();
  final String _senderReference = 'tip';
  final String _receiverReference = 'tip';
  final baseUrl = dotenv.env['API_BASE_URL'];
  bool isLoading = false;
  bool isLoadingBalance = true; // For balance loading
  String zarpBalance = '0.00'; // ZARP balance

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
      bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32)
    );

    final fullUrl = '$baseUrl/check_balance';

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
      double zarpValue = double.parse(data['zarp_balance'].toString());

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
  }

  Future<void> _sendTip() async {
    setState(() {
      isLoading = true;
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (privateKeyBase64 == null || token == null) {
      _showErrorSnackBar('Authentication error');
      setState(() {
        isLoading = false;
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
      bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32)
    );

    final fullUrl = '$baseUrl/send_zarp';

    final response = await http.post(
      Uri.parse(fullUrl),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'currency': "zarp",
        'token': token,
        'nonce': nonceBase64,
        'signature': signatureBase64,
        'receiver_phone_number': _recipientController.text,
        'amount': double.parse(_amountController.text),
        'type': 'transfer',
        'sender_reference': _senderReference,
        'receiver_reference': _receiverReference,
      }),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['message'] == 'payment_complete') {
        _showSuccessSnackBar('Tip sent successfully!');
        _fetchZarpBalance(); // Refresh balance after sending
        Navigator.pop(context);
      } else {
        _showErrorSnackBar('Failed to send tip: ${data['message']}');
      }
    } else {
      _showErrorSnackBar('Error sending tip');
    }

    setState(() {
      isLoading = false;
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Color(0xFFE98B38),
        duration: Duration(seconds: 3),
      ),
    );
  }

void _showConfirmDialog() {
  final String amountText = _amountController.text;
  final double? amount = double.tryParse(amountText);

  if (amount == null || amount <= 0) {
    _showErrorSnackBar('Please enter a valid amount');
    return;
  }

  final double currentBalance = double.tryParse(zarpBalance) ?? 0.0;

  if (amount > currentBalance) {
    _showErrorSnackBar('Insufficient ZARP balance');
    return;
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.black,
      title: Text('Confirm Tip', style: TextStyle(color: Colors.white)),
      content: Text(
        'Send $amount ZARP to ${_recipientController.text}?',
        style: TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.white)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            _sendTip();
          },
          child: Text('Confirm', style: TextStyle(color: Colors.white)),
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
        title: Text('Tip', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ZARP Balance at the top
            Container(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color(0xFFE98B38), width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    'Your ZARP Balance',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 4),
                  isLoadingBalance
                      ? SizedBox(
                          height: 36,
                          child: LinearProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE98B38)),
                            backgroundColor: Colors.grey[800],
                          ),
                        )
                      : Text(
                          '$zarpBalance ZARP',
                          style: TextStyle(
                            fontSize: 32,
                            color: Color(0xFFE98B38),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ],
              ),
            ),
            SizedBox(height: 30),

            // Amount Field
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Amount (ZARP)',
                labelStyle: TextStyle(color: Colors.white),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFE98B38)),
                ),
              ),
            ),
            SizedBox(height: 20),

            // Recipient Field
            TextFormField(
              controller: _recipientController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Recipient (@username or wallet address)',
                labelStyle: TextStyle(color: Colors.white),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFE98B38)),
                ),
              ),
            ),
            SizedBox(height: 40),

            // Send Button
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () {
                      if (_amountController.text.isNotEmpty &&
                          double.tryParse(_amountController.text) != null &&
                          double.parse(_amountController.text) > 0 &&
                          _recipientController.text.isNotEmpty) {
                        _showConfirmDialog();
                      } else {
                        _showErrorSnackBar('Please enter a valid amount and recipient');
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFE98B38),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text('Send Tip', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _recipientController.dispose();
    super.dispose();
  }
}