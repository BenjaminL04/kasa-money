import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'logged_in_home.dart'; // Import the LoggedInHomePage
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WithdrawZarpPage extends StatefulWidget {
  @override
  _WithdrawZarpPageState createState() => _WithdrawZarpPageState();
}

class _WithdrawZarpPageState extends State<WithdrawZarpPage> {
  String? selectedCountry = "South Africa";
  String? selectedBank;
  final TextEditingController accountNumberController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final baseUrl = dotenv.env['API_BASE_URL'];

  // Bank options based on country
  final Map<String, List<String>> bankOptions = {
    "South Africa": [
      "Capitec", "Standard Bank", "Nedbank", "Absa", "Investec", "First National Bank",
      "Discovery Bank", "Bank Zero", "Tyme Bank", "Access Bank South Africa", "African Bank",
      "African Bank Business", "African Bank Incorp. Ubank", "Albaraka Bank", "Bidvest Bank",
      "Capitec Business", "Citibank N.A.", "FinBond Mutual Bank", "HBZ Bank Limited",
      "HSBC Bank Plc", "JP Morgan Chase", "Nedbank Incorp. FBC", "Nedbank Ltd Incorp. PEP Bank",
      "Olympus Mobile", "OM Bank Limited", "Peoples Bank Ltd INC NBS", "S.A. Reserve Bank",
      "Sasfin Bank", "South African PostBank SOC Ltd", "Standard Chartered Bank",
      "State Bank of India", "Unibank Limited", "VBS Mutual Bank"
    ],
    "Namibia": ["Bank of Windhoek", "Standard Bank Namibia", "Nedbank Namibia", "FNB Namibia"],
  };

  @override
  void initState() {
    super.initState();
    selectedBank = bankOptions[selectedCountry]![0]; // Set default bank
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

  /// Generate signature and send withdrawal request
  Future<void> _submitWithdrawal() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (privateKeyBase64 == null || token == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Authentication data not found")));
      return;
    }

    // Generate a random nonce (16 bytes)
    final nonce = List<int>.generate(16, (i) => Random.secure().nextInt(256));
    String nonceBase64 = base64Encode(nonce);

    // Append nonce to the message
    String messageWithNonce = "$token:$nonceBase64";

    // Hash the message using SHA-256
    final messageHash = SHA256Digest().process(utf8.encode(messageWithNonce));

    // Decode private key from Base64
    Uint8List privateKeyBytes = base64Decode(privateKeyBase64);
    BigInt privateKeyInt = BigInt.parse(privateKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(), radix: 16);

    // Create ECDSA P-256 private key
    final privateKey = ECPrivateKey(privateKeyInt, ECDomainParameters('secp256r1'));

    // Initialize signer with secure random
    final signer = Signer('SHA-256/ECDSA')
      ..init(true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(privateKey), getSecureRandom()));

    // Sign the hashed message
    ECSignature signature = signer.generateSignature(Uint8List.fromList(messageHash)) as ECSignature;

    // Convert signature to Base64
    String signatureBase64 = base64Encode(bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32));

    final fullUrl = '$baseUrl/withdraw_zarp';

    // Prepare API request
    final url = Uri.parse(fullUrl);
    final body = jsonEncode({
      'token': token,
      'nonce': nonceBase64,
      'signature': signatureBase64,
      'bank_name': selectedBank,
      'account_number': accountNumberController.text,
      'country': selectedCountry,
      'amount': amountController.text,
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['message'] == 'withdrawal_complete') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => LoggedInHomePage()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unexpected response: ${responseData['message']}")));
        }
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: ${errorData['error']}")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Request failed: $e")));
    }
  }

  /// Show confirmation dialog
  void _showConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text("Confirm Withdrawal", style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Please review the details:", style: TextStyle(color: Colors.white70)),
                SizedBox(height: 10),
                Text("Country: $selectedCountry", style: TextStyle(color: Colors.white)),
                Text("Bank: $selectedBank", style: TextStyle(color: Colors.white)),
                Text("Account Number: ${accountNumberController.text}", style: TextStyle(color: Colors.white)),
                Text("Amount: ${amountController.text} ZAR", style: TextStyle(color: Colors.white)),
                Text("Fee: R10", style: TextStyle(color: Colors.white)),
                SizedBox(height: 10),
                Text("Total deduction: ${double.parse(amountController.text) + 10} ZAR", style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Cancel", style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _submitWithdrawal();
              },
              child: Text("Confirm", style: TextStyle(color: Color(0xFFE98B38))),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Send Zarp', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView( // Wrapped Column in SingleChildScrollView
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Choose country of bank",
              style: TextStyle(color: Color(0xFFE98B38), fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<String>(
              dropdownColor: Colors.grey[900],
              value: selectedCountry,
              items: ["South Africa", "Namibia"].map((String country) {
                return DropdownMenuItem<String>(
                  value: country,
                  child: Text(country, style: TextStyle(color: Colors.white)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedCountry = value;
                  selectedBank = bankOptions[value]![0];
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
            Text(
              "Choose bank",
              style: TextStyle(color: Color(0xFFE98B38), fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<String>(
              dropdownColor: Colors.grey[900],
              value: selectedBank,
              items: bankOptions[selectedCountry!]!.map((String bank) {
                return DropdownMenuItem<String>(
                  value: bank,
                  child: Text(bank, style: TextStyle(color: Colors.white)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedBank = value;
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
            TextField(
              controller: accountNumberController,
              style: TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter account number',
                hintStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            SizedBox(height: 20),
            TextField(
              controller: amountController,
              style: TextStyle(color: Colors.white),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'Enter amount in ZAR',
                hintStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            SizedBox(height: 20),
            Text(
              "Note: A fee of R10 will be charged to send the payment. Payments can take up to 5 business days to reflect",
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (accountNumberController.text.isEmpty || amountController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Please fill all fields")));
                } else {
                  _showConfirmationDialog();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFE98B38),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
              child: Text("Submit Withdrawal", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}