import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logged_in_home.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class RedeemVoucherPage extends StatefulWidget {
  @override
  _RedeemVoucherPageState createState() => _RedeemVoucherPageState();
}

class _RedeemVoucherPageState extends State<RedeemVoucherPage> {
  late CameraController _controller;
  late List<CameraDescription> cameras;
  bool _cameraPermissionGranted = false;
  bool _scanned = false;
  bool _voucherReceived = false;
  late QRViewController _qrViewController;
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  late String _authToken;
  String? _code;
  double _maxWithdrawableSats = 0;
  double _randValue = 0.0;
  String lnurl_callback = '';
  final baseUrl = dotenv.env['API_BASE_URL'];


  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _getAuthToken();
  }

  void _getAuthToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('auth_token') ?? '';
  }

  void _initializeCamera() async {
    WidgetsFlutterBinding.ensureInitialized();
    cameras = await availableCameras();
    _controller = CameraController(cameras.first, ResolutionPreset.medium);

    try {
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _cameraPermissionGranted = true;
        });
      }
    } catch (e) {
      print("Camera initialization error: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraPermissionGranted) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Redeem Voucher'),
          backgroundColor: Colors.black,
          iconTheme: IconThemeData(color: Colors.white), // Make back button white
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'Requesting Camera Permission...',
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
      title: Text(
        'Redeem Voucher',
        style: TextStyle(color: Color(0xFFE98B38)), // Set text color to 0xFFE98B38
      ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white), // Make back button white
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Redeem Your Voucher Here',
              style: TextStyle(
                fontSize: 24,
                color: Color(0xFFE98B38),
              ),
            ),
            SizedBox(height: 20),
            Container(
              width: 300,
              height: 300,
              child: _scanned
                  ? Center(
                      child: Column(
                        children: [
                          Text(
                            '${_randValue.toStringAsFixed(2)} ZAR',
                            style: TextStyle(
                              fontSize: 50,
                              color: Color(0xFFE98B38),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_maxWithdrawableSats.toStringAsFixed(2)} SATS',
                            style: TextStyle(
                              fontSize: 24,
                              color: Color(0xFFE98B38),
                            ),
                          ),
                        ],
                      ),
                    )
                  : QRView(
                      key: _qrKey,
                      onQRViewCreated: _onQRViewCreated,
                    ),
            ),
            SizedBox(height: 20),
            if (_voucherReceived)
              ElevatedButton(
                onPressed: () {
                  _redeemVoucher();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  'Redeem',
                  style: TextStyle(color: Colors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    _qrViewController = controller;
    _qrViewController.scannedDataStream.listen((scanData) {
      if (!_scanned) {
        setState(() {
          _qrViewController.pauseCamera();
          _code = scanData.code;
          _scanned = true;
          _sendPostRequest();
        });
      }
    });
  }

  Future<void> _sendPostRequest() async {
    if (_authToken.isEmpty || _code == null) {
      print('Auth token or QR code is missing');
      return;
    }

    final fullUrl = '$baseUrl/decodelnurlw';

    try {
      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'token': _authToken,
          'code': _code,
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        double maxWithdrawable = jsonResponse['maxWithdrawable'] / 1000;
        lnurl_callback = jsonResponse['callback'];
        setState(() {
          _maxWithdrawableSats = maxWithdrawable;
          _updateRandValue();
          _voucherReceived = true;
        });
      } else {
        print('Error: ${response.statusCode}, ${response.body}');
      }
    } catch (error) {
      print('Error: $error');
    }
  }

  void _updateRandValue() async {
    if (_maxWithdrawableSats == 0.0) {
      return;
    }

    try {
      final priceResponse = await http.get(Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=BTCZAR'));
      if (priceResponse.statusCode == 200) {
        final priceJson = jsonDecode(priceResponse.body);
        double price = double.parse(priceJson['price']);
        double randValue = (_maxWithdrawableSats / 100000000) * price;
        setState(() {
          _randValue = double.parse(randValue.toStringAsFixed(2));
        });
      } else {
        print('Failed to get price: ${priceResponse.statusCode}');
      }
    } catch (e) {
      print('Error getting price: $e');
    }
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

 void _redeemVoucher() async {
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

  print(lnurl_callback);
  print(_maxWithdrawableSats);

  final fullUrl = '$baseUrl/redeemvoucher';

  final url = Uri.parse(fullUrl);
  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'token': token,
      'lnurl_callback': lnurl_callback,
      'amount': _maxWithdrawableSats,
      'signature': signatureBase64,
      'nonce': nonceBase64,
    }),
  );

  if (response.statusCode == 200) {
    print('Voucher redeemed successfully: ${response.body}');
    // Check if lnurl_response is true in the response body
    Map<String, dynamic> responseBody = jsonDecode(response.body);
    if (responseBody.containsKey('lnurl_response') &&
        responseBody['lnurl_response'] == true) {
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
          title: Text("Voucher redeemed."),
        );
      },
    );
    }
  } else {
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
          title: Text("Failed to redeem Voucher"),
        );
      },
    );
  }
}
}
