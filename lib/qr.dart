import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logged_in_home.dart';
import 'dart:async';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class QrPage extends StatefulWidget {
  @override
  _QRScannerPageState createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QrPage> {
  late CameraController _controller;
  late List<CameraDescription> cameras;
  bool _cameraPermissionGranted = false;
  bool _showCamera = true;
  bool _showInput = false;
  late QRViewController _qrViewController;
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');

  TextEditingController _requestController = TextEditingController();
  TextEditingController _referenceController = TextEditingController();
  TextEditingController _amountController = TextEditingController();
  String _scannedCode = '';
  bool _isRequestInProgress = false;
  String? _zarAmount;
  int? _satsAmount;
  bool _isInvoiceExpired = false;
  bool _isInvoiceFailed = false;
  bool _showPayButton = false;
  bool _isButtonEnabled = true;

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



  void _logAmountAndComment() {
    try {
      double amount = double.parse(_amountController.text);
      String comment = _referenceController.text;

      double convertedAmount = (amount / _btcZarExchangeRate) * 100000000000;
      int roundedConvertedAmount = (convertedAmount / 1000).round() * 1000;


      // Call the method to send data to the endpoint
      _sendPayRequest2(roundedConvertedAmount, comment);
    } catch (error) {
    }
  }

 Future<void> _sendPayRequest2(int roundedConvertedAmount, String comment) async {
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

    try {
      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'token': token,
          'amount': roundedConvertedAmount,
          'callback': _callback,
          'description': _description,
          'description_hash': _descriptionHash,
          'comment': comment,
          'signature': signatureBase64,
          'nonce': nonceBase64,
        }),
      );

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        final innerResponse = jsonDecode(decodedResponse['response']);

        String paymentHash = innerResponse['payment_hash'];
        String checkingId = innerResponse['checking_id'];

        if (paymentHash != null && checkingId != null) {
          _showPaymentSuccessfulPopup();
          _navigateToLoggedInHomePageAfterDelay();
        } else {
          _showPaymentUnsuccessfulPopup();
          _navigateToLoggedInHomePageAfterDelay();
        }
      } else {
        _showPaymentUnsuccessfulPopup();
        _navigateToLoggedInHomePageAfterDelay();
      }
    } catch (error) {
      _showPaymentUnsuccessfulPopup();
      _navigateToLoggedInHomePageAfterDelay();
    }
  }

  void _showPaymentSuccessfulPopup() {
    showDialog(
      context: context,
      builder: (context) {
        Future.delayed(Duration(seconds: 3), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => LoggedInHomePage(),
            ),
          );
        });

        return AlertDialog(
          title: Text('Payment Successful'),
        );
      },
    );
  }

  void _showPaymentUnsuccessfulPopup() {
    showDialog(
      context: context,
      builder: (context) {
        Future.delayed(Duration(seconds: 3), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => LoggedInHomePage(),
            ),
          );
        });

        return AlertDialog(
          title: Text('Payment Unsuccessful'),
        );
      },
    );
  }

  void _navigateToLoggedInHomePageAfterDelay() {
    Future.delayed(Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LoggedInHomePage(),
        ),
      );
    });
  }

  String _callback = '';
  String _description = '';
  String _descriptionHash = '';


  @override
  void initState() {
    super.initState();  
    _fetchBtcZarExchangeRate(); // Fetch exchange rate when the widget initializes
    _initializeCamera();
  }
  
  double _btcZarExchangeRate = 0.0;

  Future<void> _fetchBtcZarExchangeRate() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=BTCZAR'),
      );

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        _btcZarExchangeRate = double.parse(decodedResponse['price']);
      } else {
        print('Error fetching BTC/ZAR exchange rate: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching BTC/ZAR exchange rate: $error');
    }
  }


  void _initializeCamera() async {
    cameras = await availableCameras();
    _controller = CameraController(cameras.first, ResolutionPreset.medium);
    await _controller.initialize();
    if (mounted) {
      setState(() {
        _cameraPermissionGranted = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _qrViewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraPermissionGranted) {
      return Scaffold(
        appBar: AppBar(
        title: Text(
          'QR Scanner Page',
          style: TextStyle(color: Color(0xFFE98B38)), 
        ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black, // <-- Add this line here
      appBar: AppBar(
        backgroundColor: Colors.black, // Set background color to black
        iconTheme: IconThemeData(color: Colors.white),
        title: Text('QR Scanner Page',
        style: TextStyle(color: Color(0xFFE98B38)), 
        ),
      ),
      body: Center(
        child: _showCamera
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 400,
                    height: 400,
                    child: QRView(
                      key: _qrKey,
                      onQRViewCreated: _onQRViewCreated,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _showInput = true;
                        _showCamera = false;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black, // Set background color to white
                      foregroundColor: Colors.white, // Set text color to black
                      side: BorderSide(
                        color: Colors.white,
                        width: 1.0,
                      ),
                    ),
                    child: Text('Input Manually'),
                  )
                ],
              )
            : _showInput
                ? _buildInputForm()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _getScannedCodeMessage(),
                        style: TextStyle(
                          fontSize: 20,
                          color: Color(0xFFE98B38), 
                        ),
                      ),
                      SizedBox(height: 10),
                      _buildDynamicUI(),
                      SizedBox(height: 20),
                      _showPayButton
                          ? ElevatedButton(
                            onPressed: _isButtonEnabled
                            ? () {
                              setState(() {
                                _isButtonEnabled = false; // Disable the button
                              });
                              _logAmountAndComment();
                            }
                            : null,
                            style: ElevatedButton.styleFrom(
                              minimumSize: Size(double.infinity, 60),
                              backgroundColor: Colors.black, // Set background color to white
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white,
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              'Pay',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                          : Container(),
                      SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _showCamera = true;
                            _scannedCode = '';
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white,
                            width: 1.0,
                          ),
                          minimumSize: _showPayButton
                              ? Size(double.infinity, 40)
                              : Size(double.infinity, 60),
                        ),
                        child: Text('Scan Again'),
                      ),
                    ],
                  ),
      ),
      
    );
  }

  Widget _buildDynamicUI() {
    if (_scannedCode.startsWith('lnbc') || _scannedCode.contains('LNBC')) {
      return Column(
        children: [
          if (_isInvoiceExpired)
            Text(
              'Invoice has Expired',
              style: TextStyle(fontSize: 16, color: Colors.red),
            )
          else ...[
            if (_zarAmount != null)
              Text(
                '$_zarAmount ZAR',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFE98B38)),
              ),
            if (_satsAmount != null)
              Text(
                '$_satsAmount sats',
                style: TextStyle(fontSize: 16),
              ),
            ElevatedButton(
              onPressed: _isInvoiceExpired
                  ? null
                  : () {
                      _sendPayRequest(_scannedCode);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black, // Set background color to white
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: Colors.white,
                  width: 1.0,
                ),
              ),
              child: Text('Pay'),
            ),
          ],
        ],
      );
    } else if (_scannedCode.startsWith('LNURL') || _scannedCode.contains('@') || _scannedCode.contains('lnurl')) {
      return _buildPaymentForm();
    } else {
      return Text('Not a valid request');
    }
  }

  Widget _buildPaymentForm() {
    return Column(
      children: [
        TextField(
          controller: _referenceController,
          maxLength: 32,
          style: TextStyle(color: Colors.white), // Set inputted text color to white
          decoration: InputDecoration(
            hintText: 'Enter reference (alphanumeric, max 32 characters)',
            hintStyle: TextStyle(color: Colors.white), // Set hint text color to white
            filled: true, // Make the input field filled
            fillColor: Colors.black, // Set background color to black
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set border color to white
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set enabled border color to white
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set focused border color to white
            ),
          ),
        ),
        SizedBox(height: 10),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          style: TextStyle(color: Colors.white), // Set inputted text color to white
          decoration: InputDecoration(
            hintText: 'Enter amount',
            hintStyle: TextStyle(color: Colors.white), // Set hint text color to white
            filled: true, // Make the input field filled
            fillColor: Colors.black, // Set background color to black
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set border color to white
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set enabled border color to white
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Set focused border color to white
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Type in request',
          style: TextStyle(
            fontSize: 20,
            color: Color(0xFFE98B38), 
          ),
        ),
        SizedBox(height: 20),
        TextField(
          controller: _requestController,
          decoration: InputDecoration(
            hintText: 'Enter your request',
            hintStyle: TextStyle(color: Colors.black), // Hint text color
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Outline color
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Enabled border color
                      ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white), // Focused border color
            ),
            filled: true, // Make the input field filled
            fillColor: Colors.white, // Fill color (for the input field background)
          ),
        ),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            _submitManualInput();
          },
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, 60),
            backgroundColor: Colors.black, // Set background color to white
            foregroundColor: Colors.white, // Set text color to black
            side: BorderSide(
              color: Colors.white,
              width: 1.0,
            ),
          ),
          child: Text('Submit', style: TextStyle(fontSize: 20)),
        ),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _showCamera = true;
              _showInput = false;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black, // Set background color to white
            foregroundColor: Colors.white,
            side: BorderSide(
              color: Colors.white,
              width: 1.0,
            ),
          ),
          child: Text('Cancel'),
        ),
      ],
    );
  }

  bool _hasScanned = false;

void _onQRViewCreated(QRViewController controller) {
  setState(() {
    _qrViewController = controller;
  });

  controller.scannedDataStream.listen((scanData) {
    if (!_hasScanned) {
      _hasScanned = true; // Set the flag to true to indicate that the callback has been executed

      setState(() {
        _scannedCode = scanData.code ?? 'No data';
        _showCamera = false;
        _showInput = false;
        _isInvoiceExpired = false;
        _isInvoiceFailed = false;
        _showPayButton = _scannedCode.startsWith('LNURL') || _scannedCode.contains('@') || _scannedCode.contains('lnurl');
      });

      if (_scannedCode.startsWith('lnbc') || _scannedCode.contains('LNBC')) {
        _sendPostRequest(_scannedCode);
      } else if (_scannedCode.startsWith('LNURL') || _scannedCode.contains('@') || _scannedCode.contains('lnurl')) {
        _sendDecodeLNURLRequest(_scannedCode);
        print(_scannedCode);
      }
    }
  });
}


  String _getScannedCodeMessage() {
    if (_scannedCode.startsWith('lnbc') ||
        _scannedCode.startsWith('LNURL') ||
        _scannedCode.contains('@') ||
        _scannedCode.contains('LNBC') ||
        _scannedCode.contains('lnurl')) {
      return 'Scanned QR Code:';
    } else {
      return 'Not a valid request';
    }
  }

  void _submitManualInput() {
    setState(() {
      _scannedCode = _requestController.text;
      _showInput = false;
      _showCamera = false;
      _isInvoiceExpired = false;
      _isInvoiceFailed = false;
      _showPayButton = _scannedCode.startsWith('LNURL') || _scannedCode.contains('@') || _scannedCode.contains('lnurl');
    });

    if (_scannedCode.startsWith('lnbc') || _scannedCode.contains('LNBC')) {
      _sendPostRequest(_scannedCode);
    } else if (_scannedCode.startsWith('LNURL') || _scannedCode.contains('@') || _scannedCode.contains('lnurl')) {
      _sendDecodeLNURLRequest(_scannedCode);
    }
  }

  Future<void> _sendPostRequest(String bolt11) async {
    if (_isRequestInProgress) {
      return;
    }

    setState(() {
      _isRequestInProgress = true;
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? authToken = prefs.getString('auth_token');

    if (authToken == null) {
      print('Error: Auth token not found in shared preferences');
      setState(() {
        _isRequestInProgress = false;
      });
      return;
    }

    Map<String, String> data = {
      'bolt11': bolt11,
      'token': authToken,
    };

    final fullUrl1 = '$baseUrl/decodeinvoice';

    try {
      final response = await http.post(
        Uri.parse(fullUrl1),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);

        if (decodedResponse['status'] == 'expired') {
          setState(() {
            _isInvoiceExpired = true;
          });
        } else if (decodedResponse['status'] == 'failed') {
          setState(() {
            _isInvoiceFailed = true;
          });
        } else {
          setState(() {
            _zarAmount = decodedResponse['ZAR']?.toString();
            _satsAmount = decodedResponse['sat'];
          });
          print('Response: ${response.body}');
        }
      } else {
        print('Error: ${response.statusCode}, ${response.body}');
      }
    } catch (error) {
      print('Error: $error');
    } finally {
      setState(() {
        _isRequestInProgress = false;
      });
    }
  }

  Future<void> _sendPayRequest(String bolt11) async {
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

    Map<String, String> data = {
      'bolt11': bolt11,
      'token': token,
      'signature': signatureBase64,
      'nonce': nonceBase64,
    };

    final fullUrl3 = '$baseUrl/payln';

    try {
      final response = await http.post(
        Uri.parse(fullUrl3),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );
      print(response.body);

      final decodedResponse = jsonDecode(response.body);

        if (decodedResponse.containsKey('checking_id')) {
          setState(() {
            _isInvoiceExpired = true;
          });
          _showPaidMessage();
        } else {
          setState(() {
            _isInvoiceFailed = true;
          });
          print('Payment Failed: ${response.body}');
          _showPaidMessage();
        }
      } catch (error) {
        print('Pay Error: $error');
      }
  }

  Future<void> _sendDecodeLNURLRequest(String lnurl) async {
    if (_isRequestInProgress) {
      return;
    }

    setState(() {
      _isRequestInProgress = true;
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? authToken = prefs.getString('auth_token');

    if (authToken == null) {
      print('Error: Auth token not found in shared preferences');
      setState(() {
        _isRequestInProgress = false;
      });
      return;
    }

    Map<String, String> data = {
      'lnurl': lnurl,
      'token': authToken,
    };

    final fullUrl2 = '$baseUrl/decodelnurl';

    try {
      final response = await http.post(
        Uri.parse(fullUrl2),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),

      );

      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);

        if (decodedResponse['response'] != null) {
          final innerResponse = jsonDecode(decodedResponse['response']);
          _callback = innerResponse['callback'];
          _description = innerResponse['description'];
          _descriptionHash = innerResponse['description_hash'];



        } else {
        }
      } else {
      }
    } catch (error) {
    } finally {
      setState(() {
        _isRequestInProgress = false;
      });
    }
  }

  void _showPaidMessage() {
    showDialog(
      context: context,
      builder: (context) {
        Future.delayed(Duration(seconds: 3), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => LoggedInHomePage(),
            ),
          );
        });

        return AlertDialog(
          title: Text(_isInvoiceFailed ? 'Invoice already paid' : 'Paid'),
        );
      },
    );
  }
}
