import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class SendNumber extends StatefulWidget {
  @override
  _SendNumberState createState() => _SendNumberState();
}

class _SendNumberState extends State<SendNumber> {
  TextEditingController _amountController = TextEditingController();
  TextEditingController _referenceController = TextEditingController();
  TextEditingController phoneNumberController = TextEditingController();
  String selectedCountryCode = "+27";
  final baseUrl = dotenv.env['API_BASE_URL'];


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Send Page',
          style: TextStyle(color: Color(0xFFE98B38)),
        ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Type in the number you want to send to',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            SizedBox(height: 16.0),
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
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedCountryCode = value!;
                      });
                    },
                    style: TextStyle(color: Color(0xFFFF9B29)),
                    decoration: InputDecoration(
                      labelText: 'Country',
                      labelStyle: TextStyle(color: Colors.white),
                      hintText: "Select Country",
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
                      labelText: 'Phone Number',
                      hintText: '123456789',
                      labelStyle: TextStyle(color: Colors.white),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value?.isEmpty ?? true) {
                        return 'Please enter your phone number';
                      } else if (value!.startsWith('0')) {
                        return 'Phone number cannot start with 0';
                      } else if (value.length != 9) {
                        return 'Phone number must be 9 digits';
                      }
                      return null;
                    },
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () async {
                String formattedNumber = '${selectedCountryCode.substring(1)}${phoneNumberController.text}@bitcoinkhaya.com';
                String? authToken = await _retrieveAuthToken();
                if (authToken != null) {
                  await _sendApiRequest(authToken, formattedNumber, context);
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
              child: Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

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

  Future<String?> _retrieveAuthToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }
  Future<void> _sendApiRequest(String authToken, String lnurl, BuildContext context) async {
    final fullUrl = '$baseUrl/decodelnurl';
    final Uri endpoint = Uri.parse(fullUrl);
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
    };
    final Map<String, String> body = {
      'token': authToken,
      'lnurl': lnurl,
    };

    try {
      final response = await http.post(
        endpoint,
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> jsonResponse = json.decode(response.body);
        Map<String, dynamic> callbackData = _extractCallback(jsonResponse);

        String? callback = callbackData['callback'];
        String? description_hash = callbackData['description_hash'];
        String? description = callbackData['description'];

        if (callback != null) {
          _showPopup(authToken, callback, description, description_hash, context);
        } else {
          _refreshPage();
        }
      } else {
        _refreshPage();
        _showErrorPopup(context, 'Failed to decode LNURL. Try again.');
      }
    } catch (error) {
      _refreshPage();
      _showErrorPopup(context, 'Failed to decode LNURL. Try again.');
    }
  }

  Map<String, dynamic> _extractCallback(Map<String, dynamic> jsonResponse) {
    try {
      String responseString = jsonResponse['response'];
      Map<String, dynamic> responseJson = json.decode(responseString);

      // Extract the callback, description, and description_hash
      String callback = responseJson['callback'];
      String description_hash = responseJson['description_hash'];
      String description = responseJson['description'];

      return {
        'callback': callback,
        'description_hash': description_hash,
        'description': description,
      };
    } catch (e) {
      return {
        'callback': null,
        'description_hash': null,
        'description': null,
      };
    }
  }

  void _showPopup(String authToken, String callback, String? description, String? description_hash, BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevents closing the popup with a tap outside
      builder: (BuildContext context) {
        return FutureBuilder<double>(
          // Fetch the Binance price asynchronously
          future: _fetchBinancePrice(),
          builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                title: Text('Popup'),
                content: CircularProgressIndicator(),
              );
            } else if (snapshot.hasError) {
              return AlertDialog(
                title: Text('Error'),
                content: Text('Error fetching Binance price: ${snapshot.error}'),
                actions: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // Close the popup
                    },
                    child: Text('Close'),
                  ),
                ],
              );
            } else {
              return AlertDialog(
                title: Text('Popup'),
                content: Column(
                  children: [
                    TextField(
                      controller: _amountController,
                      decoration: InputDecoration(labelText: 'Amount in Rands'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: _referenceController,
                      decoration: InputDecoration(labelText: 'Comment'),
                      keyboardType: TextInputType.text,
                    ),
                    if (snapshot.hasData) ...[
                      Text(
                        '1 BTC = ${snapshot.data} ZAR', // Display the Binance price
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () async {
                      // Add your custom logic for the button

                      // Validate inputs
                      String amountText = _amountController.text;
                      String comment = _referenceController.text;

                      if (amountText.isEmpty || comment.isEmpty) {
                        _showErrorPopup(context, 'Please enter both amount and comment.');
                        return;
                      }

                      // Parse the entered amount to double
                      double enteredAmount = double.tryParse(amountText) ?? 0.0;

                      if (snapshot.hasData) {
                        // Calculate the converted amount
                        double binancePrice = snapshot.data!;
                        double convertedAmount = (enteredAmount / binancePrice) * 1e11;

                        // Round to the nearest 1000
                        double roundedAmount = (convertedAmount / 1000).round() * 1000;

                        await _sendPayLnurlRequest(authToken, roundedAmount, callback, comment, description ?? '', description_hash ?? '', context);
                      } else {
                        _showErrorPopup(context, 'Error fetching Binance price');
                      }
                    },
                    child: Text('Submit'),
                  ),
                ],
              );
            }
          },
        );
      },
    );
  }

  Future<double> _fetchBinancePrice() async {
    try {
      final response = await http.get(Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=BTCZAR'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return double.tryParse(data['price']) ?? 0.0;
      } else {
        return 0.0;
      }
    } catch (error) {
      return 0.0;
    }
  }

  Future<void> _sendPayLnurlRequest(String authToken, double amount, String callback, String comment, String description, String description_hash, BuildContext context) async {

        SharedPreferences prefs = await SharedPreferences.getInstance();
    // String authToken = prefs.getString('auth_token') ?? '';


    // Retrieve private key and auth token from SharedPreferences
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (privateKeyBase64 == null || token == null) {
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

    final fullUrl = '$baseUrl/paylnurl';

    final Uri endpoint = Uri.parse(fullUrl);
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
    };
    final Map<String, dynamic> body = {
      'token': token,
      'amount': amount,
      'callback': callback,
      'comment': comment,
      'description': description,
      'description_hash': description_hash,
      'signature': signatureBase64,
      'nonce': nonceBase64,
    };

    try {
      final response = await http.post(
        endpoint,
        headers: headers,
        body: jsonEncode(body),
      );
      print(response.body);

      if (response.statusCode == 200) {
        Map<String, dynamic> jsonResponse = json.decode(response.body);

        if (jsonResponse['response'] != null) {
          Map<String, dynamic> responseData = json.decode(jsonResponse['response']);
          if (responseData.containsKey('payment_hash')) {
            // Payment successful

            _navigateToLoggedInHomePage(context);
            return;
          }
        }

        // Payment failed
        _showErrorPopup(context, 'Payment Failed. Try again.');
      } else {
        _showErrorPopup(context, 'Payment Failed. Try again.');
      }
    } catch (error) {
      _showErrorPopup(context, 'Payment Failed. Try again.');
    }
  }

  void _navigateToLoggedInHomePage(BuildContext context) {
    // Replace this with your actual navigation logic
    Navigator.pushReplacementNamed(context, '/logged_in_home');
  }

  void _refreshPage() {
  }

  void _showErrorPopup(BuildContext context, String errorMessage) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text(errorMessage),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close the error popup
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class PhoneNumberInput extends StatefulWidget {
  @override
  _PhoneNumberInputState createState() => _PhoneNumberInputState();
}

class _PhoneNumberInputState extends State<PhoneNumberInput> {
  static TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      style: TextStyle(color: Colors.white), // Make input text white
      decoration: InputDecoration(
        labelText: 'Phone Number',
        labelStyle: TextStyle(color: Colors.white), // Make label text white
        hintText: '123456789',
        hintStyle: TextStyle(color: Colors.white70), // Make hint text white with slight transparency
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white), // White underline when not focused
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white), // White underline when focused
        ),
      ),
      keyboardType: TextInputType.phone,
      maxLength: 9,
      inputFormatters: [
        FilteringTextInputFormatter.singleLineFormatter,
        TextInputFormatter.withFunction((oldValue, newValue) {
          if (newValue.text.isNotEmpty && newValue.text.startsWith('0')) {
            return oldValue;
          }
          return newValue;
        }),
      ],
      validator: (value) {
        if (value?.isEmpty ?? true) {
          return 'Please enter your phone number';
        } else if (value!.length != 9) {
          return 'Phone number must be 9 digits';
        }
        return null;
      },
    );
  }
}
