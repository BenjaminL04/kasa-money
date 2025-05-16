import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ReceiveZarpPage extends StatefulWidget {
  @override
  _ReceiveZarpPageState createState() => _ReceiveZarpPageState();
}

class _ReceiveZarpPageState extends State<ReceiveZarpPage> {
  String? selectedCountry = "South Africa";
  String username27 = '';

  final baseUrl = dotenv.env['API_BASE_URL'];

  @override
  void initState() {
    super.initState();
    _sendPostRequest(); // Fetch the username on page load
  }

  /// Secure random generator for cryptographic operations
  SecureRandom getSecureRandom() {
    final secureRandom = SecureRandom('Fortuna')
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => Random.secure().nextInt(256)))));
    return secureRandom;
  }

  /// Converts a BigInt to Uint8List of specified length
  Uint8List bigIntToBytes(BigInt number, int byteLength) {
    final byteList = number.toRadixString(16).padLeft(byteLength * 2, '0');
    return Uint8List.fromList(List.generate(byteLength, (i) {
      return int.parse(byteList.substring(i * 2, i * 2 + 2), radix: 16);
    }));
  }

  /// Fetches username starting with "27" from API
  Future<void> _sendPostRequest() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? privateKeyBase64 = prefs.getString('private_key');
      String? token = prefs.getString('auth_token');

      if (privateKeyBase64 == null || token == null) {
        return;
      }

      // Generate a random nonce (16 bytes)
      final nonce = List<int>.generate(16, (i) => Random.secure().nextInt(256));
      String nonceBase64 = base64Encode(nonce);

      // Hash the message using SHA-256
      final messageHash = SHA256Digest().process(utf8.encode("$token:$nonceBase64"));

      // Decode private key
      Uint8List privateKeyBytes = base64Decode(privateKeyBase64);
      BigInt privateKeyInt = BigInt.parse(
          privateKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(),
          radix: 16);

      // Create ECDSA private key
      final privateKey = ECPrivateKey(privateKeyInt, ECDomainParameters('secp256r1'));

      // Sign message hash
      final signer = Signer('SHA-256/ECDSA')
        ..init(true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(privateKey), getSecureRandom()));
      ECSignature signature = signer.generateSignature(Uint8List.fromList(messageHash)) as ECSignature;

      // Convert signature to Base64
      String signatureBase64 = base64Encode(
        bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32)
      );

      // API request
      final apiUrl = '$baseUrl/get_lnurls';
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'signature': signatureBase64,
          'nonce': nonceBase64,
        }),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        for (var item in data) {
          if (item['username'].startsWith('27') || item['username'].startsWith('264')) {

            setState(() {
              username27 = item['username'];
            });
            break;
          }
        }
      }
    } catch (e) {
      print("Error fetching username: $e");
    }
  }

  /// Returns dynamically updated bank details based on selected country
  String getBankDetails(String country) {
    return country == "South Africa"
        ? "Deposit from a South African bank account only (No foreign currency transactions will be accepted):\n\n"
            "Bank: Bank Zero\n"
            "Branch Code: 888000\n"
            "Account Holder: Kasa Money (Pty) Ltd\n"
            "Bank Account number: 80204818597\n"
            "Reference: $username27\n\n"
            "Use this reference to make sure that the funds get credited to your account and not someone else's. "
            "It may take up to 3 business days for the deposit to reflect in your account. For any Deposit related queries please send an email to help@kasamoney.com and we will assist."
        : "Deposit from a Namibian bank account only (No foreign currency transactions will be accepted):\n\n"
            "Bank: Standard Bank Namibia\n"
            "Branch code: 087373\n"
            "Account Holder: Kasa Money (Pty) Ltd\n"
            "Account Number: 98743250\n"
            "Reference: $username27\n\n"
            "Use this reference to make sure that the funds get credited to your account and not someone else's. "
            "It may take up to 3 business days for the deposit to reflect in your account. For any Deposit related queries please send an email to help@kasamoney.com and we will assist.";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Choose which country to deposit from",
              style: TextStyle(color: Color(0xFFE98B38), fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<String>(
              dropdownColor: Colors.grey[900],
              value: selectedCountry,
              items: ["South Africa", "Namibia"].map((String country) {
                return DropdownMenuItem<String>(
                  value: country,
                  child: Text(
                    country,
                    style: TextStyle(color: Colors.white),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedCountry = value;
                });
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(height: 20),
            if (selectedCountry != null)
              Text(
                getBankDetails(selectedCountry!),
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
          ],
        ),
      ),
    );
  }
}
