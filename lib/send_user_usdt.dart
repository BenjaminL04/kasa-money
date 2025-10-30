import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/digests/sha256.dart';
import 'logged_in_home.dart'; // Import the LoggedInHomePage
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SendUserUsdtPage extends StatefulWidget {
  @override
  _SendUserUsdtPageState createState() => _SendUserUsdtPageState();
}

class _SendUserUsdtPageState extends State<SendUserUsdtPage> {
  String? selectedCountryCode = '+27';
  final phoneNumberController = TextEditingController();
  final amountController = TextEditingController();
  final senderReferenceController = TextEditingController();
  final receiverReferenceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final baseUrl = dotenv.env['API_BASE_URL'];

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

  Future<void> sendUsdtTransaction(String receiverInput) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // Retrieve private key and auth token from SharedPreferences
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (privateKeyBase64 == null || token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: Missing private key or token')),
      );
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

    // Convert private key bytes to BigInt
    BigInt privateKeyInt = BigInt.parse(privateKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(), radix: 16);

    // Create ECDSA P-256 private key
    final privateKey = ECPrivateKey(privateKeyInt, ECDomainParameters('secp256r1'));

    // Initialize secure random generator
    final secureRandom = getSecureRandom();

    // Initialize ECDSA signer with SecureRandom
    final signer = Signer('SHA-256/ECDSA')
      ..init(true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(privateKey), secureRandom));

    // Sign the hashed message
    ECSignature signature = signer.generateSignature(Uint8List.fromList(messageHash)) as ECSignature;

    // Convert signature to Base64
    String signatureBase64 = base64Encode(
      bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32)
    );

    // Prepare receiver_phone_number: prepend country code only if not username
    String receiverPhoneNumber = receiverInput;
    if (selectedCountryCode != null) {
      String cleanCountryCode = selectedCountryCode!.replaceAll('+', '');
      receiverPhoneNumber = '$cleanCountryCode$receiverInput';
    }

    final fullUrl = '$baseUrl/send_zarp';

    // Send request to API
    final url = Uri.parse(fullUrl);
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'currency': "usdt",
        'token': token,
        'nonce': nonceBase64,
        'signature': signatureBase64,
        'receiver_phone_number': receiverPhoneNumber,
        'amount': double.parse(amountController.text),
        'type': 'transfer',
        'sender_reference': senderReferenceController.text.isEmpty ? null : senderReferenceController.text,
        'receiver_reference': receiverReferenceController.text.isEmpty ? null : receiverReferenceController.text,
      }),
    );

    final responseData = jsonDecode(response.body);
    if (responseData['message'] == 'payment_complete') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment completed successfully')),
      );
      Navigator.pop(context); // Close the dialog
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoggedInHomePage()),
      );
    } else {
      final error = responseData['error'] ?? 'Unknown error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    }
  }

  void showAmountDialog(String receiverInput) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text('Send USDT', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  labelStyle: TextStyle(color: Colors.white),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Please enter an amount';
                  if (double.tryParse(value!) == null || double.parse(value) <= 0) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: senderReferenceController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Sender Reference (Optional)',
                  labelStyle: TextStyle(color: Colors.white),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
              ),
              TextFormField(
                controller: receiverReferenceController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Receiver Reference (Optional)',
                  labelStyle: TextStyle(color: Colors.white),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              if (amountController.text.isNotEmpty && double.tryParse(amountController.text) != null) {
                sendUsdtTransaction(receiverInput);
              }
            },
            child: Text('Send', style: TextStyle(color: Colors.white)),
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
        iconTheme: IconThemeData(color: Colors.white),
        title: Text('Send USDT', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      value: selectedCountryCode,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: "+27",
                          child: Text("South Africa (+27)", overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: "+264",
                          child: Text("Namibia (+264)", overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: null,
                          child: Text("Username", overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedCountryCode = value;
                          phoneNumberController.clear(); // Clear input when switching
                        });
                      },
                      style: TextStyle(color: Color(0xFFFF9B29)),
                      decoration: InputDecoration(
                        labelText: 'Type',
                        labelStyle: TextStyle(color: Colors.white),
                        hintText: "Select Type",
                        hintStyle: TextStyle(color: Colors.white),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: TextFormField(
                      controller: phoneNumberController,
                      decoration: InputDecoration(
                        labelText: selectedCountryCode == null ? 'Username' : 'Phone Number',
                        hintText: selectedCountryCode == null ? 'e.g., johndoe' : '123456789',
                        labelStyle: TextStyle(color: Colors.white),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                      ),
                      keyboardType: selectedCountryCode == null ? TextInputType.text : TextInputType.phone,
                      validator: (value) {
                        if (value?.isEmpty ?? true) {
                          return selectedCountryCode == null ? 'Please enter a username' : 'Please enter a phone number';
                        }
                        if (selectedCountryCode == null) {
                          // Username validation
                          if (value!.contains(' ')) {
                            return 'Username cannot contain spaces';
                          }
                          if (value != value.toLowerCase()) {
                            return 'Username must be all lowercase';
                          }
                          if (!RegExp(r'^[a-z0-9_-]{3,30}$').hasMatch(value)) {
                            return 'Username must be 3-30 characters, using only letters, numbers, underscores, or hyphens';
                          }
                        } else {
                          // Phone number validation
                          if (value!.startsWith('0')) {
                            return 'Phone number cannot start with 0';
                          }
                          if (value.length != 9) {
                            return 'Phone number must be 9 digits';
                          }
                          if (!RegExp(r'^\d+$').hasMatch(value)) {
                            return 'Phone number must contain only digits';
                          }
                        }
                        return null;
                      },
                      style: TextStyle(color: Colors.white),
                      onChanged: (value) {
                        if (selectedCountryCode == null) {
                          // Force lowercase for username input
                          if (value != value.toLowerCase()) {
                            phoneNumberController.value = TextEditingValue(
                              text: value.toLowerCase(),
                              selection: phoneNumberController.selection,
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    showAmountDialog(phoneNumberController.text);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFFF9B29),
                  foregroundColor: Colors.black,
                ),
                child: Text('Next'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}