import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointycastle/pointycastle.dart' hide Padding;
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/api.dart' hide Padding;
import 'package:pointycastle/digests/sha256.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class BalancesPage extends StatefulWidget {
  final String satsBalance;
  final String zarBalance;
  final String zarpBalance;

  const BalancesPage({
    Key? key,
    required this.satsBalance,
    required this.zarBalance,
    required this.zarpBalance,
  }) : super(key: key);

  @override
  _BalancesPageState createState() => _BalancesPageState();
}

class _BalancesPageState extends State<BalancesPage> {
  bool _isSwapped = false;
  final TextEditingController _btcController = TextEditingController();
  final TextEditingController _zarpController = TextEditingController();
  double _btcZarPrice = 0.0;
  Timer? _priceUpdateTimer;
  String? _errorMessage;
  String? _lastBtcText;
  String? _lastZarpText;
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

  @override
  void initState() {
    super.initState();
    _fetchPrice();
    _priceUpdateTimer = Timer.periodic(Duration(seconds: 60), (_) {
      _fetchPrice();
      if (_isSwapped && _zarpController.text.isNotEmpty) {
        _updateConversion(_zarpController, _btcController);
      } else if (!_isSwapped && _btcController.text.isNotEmpty) {
        _updateConversion(_btcController, _zarpController);
      } else if (_isSwapped && _btcController.text.isNotEmpty) {
        _updateConversion(_btcController, _zarpController);
      } else if (!_isSwapped && _zarpController.text.isNotEmpty) {
        _updateConversion(_zarpController, _btcController);
      }
    });
    
    _btcController.addListener(() => _updateConversion(_btcController, _zarpController));
    _zarpController.addListener(() => _updateConversion(_zarpController, _btcController));
  }

  Future<void> _fetchPrice() async {
    try {
      final response = await http.get(Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=BTCZAR'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _btcZarPrice = double.parse(data['price']);
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  void _updateConversion(TextEditingController source, TextEditingController target) {
    if (source == _btcController && source.text == _lastBtcText) return;
    if (source == _zarpController && source.text == _lastZarpText) return;

    setState(() {
      double satsBalance = double.tryParse(widget.satsBalance) ?? 0;
      double zarpBalance = double.tryParse(widget.zarpBalance) ?? 0;

      if (_isSwapped) {
        if (source == _zarpController && _zarpController.text.isNotEmpty) {
          double zarAmount = double.tryParse(_zarpController.text) ?? 0;
          double satsAmount = (zarAmount / _btcZarPrice) * 100000000 * 0.95;
          _lastBtcText = satsAmount.toStringAsFixed(0);
          _btcController.text = _lastBtcText!;
          _errorMessage = zarAmount > zarpBalance ? "This amount exceeds your balance." : null;
          _lastZarpText = _zarpController.text;
        } else if (source == _btcController && _btcController.text.isNotEmpty) {
          double satsAmount = double.tryParse(_btcController.text) ?? 0;
          double zarAmount = (satsAmount * _btcZarPrice) / 100000000 / 0.95;
          _lastZarpText = zarAmount.toStringAsFixed(2);
          _zarpController.text = _lastZarpText!;
          _errorMessage = null;
          _lastBtcText = _btcController.text;
        }
      } else {
        if (source == _btcController && _btcController.text.isNotEmpty) {
          double satsAmount = double.tryParse(_btcController.text) ?? 0;
          double zarAmount = (satsAmount * _btcZarPrice) / 100000000 * 0.95;
          _lastZarpText = zarAmount.toStringAsFixed(2);
          _zarpController.text = _lastZarpText!;
          _errorMessage = satsAmount > satsBalance ? "This amount exceeds your balance." : null;
          _lastBtcText = _btcController.text;
        } else if (source == _zarpController && _zarpController.text.isNotEmpty) {
          double zarAmount = double.tryParse(_zarpController.text) ?? 0;
          double satsAmount = (zarAmount / _btcZarPrice) * 100000000 / 0.95;
          _lastBtcText = satsAmount.toStringAsFixed(0);
          _btcController.text = _lastBtcText!;
          _errorMessage = null;
          _lastZarpText = _zarpController.text;
        }
      }

      if (_btcController.text.isEmpty && _zarpController.text.isEmpty) {
        _errorMessage = null;
      }
    });
  }

  void _swapCurrencies() async {
    setState(() {
      _isSwapped = !_isSwapped;
      _btcController.clear();
      _zarpController.clear();
      _lastBtcText = null;
      _lastZarpText = null;
      _errorMessage = null;
    });
    
    await _fetchPrice();
    _updateConversion(_btcController, _zarpController);
  }

  Future<void> _performSwap() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? privateKeyBase64 = prefs.getString('private_key');
      String? token = prefs.getString('auth_token');

      if (privateKeyBase64 == null || token == null) {
        setState(() => _errorMessage = "Authentication credentials not found");
        return;
      }

      final nonce = List<int>.generate(16, (i) => Random.secure().nextInt(256));
      String nonceBase64 = base64Encode(nonce);
      String messageWithNonce = "$token:$nonceBase64";
      final messageHash = SHA256Digest().process(utf8.encode(messageWithNonce));

      Uint8List privateKeyBytes = base64Decode(privateKeyBase64);
      BigInt privateKeyInt = BigInt.parse(
          privateKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(),
          radix: 16);
      final privateKey = ECPrivateKey(privateKeyInt, ECDomainParameters('secp256r1'));
      final secureRandom = getSecureRandom();

      final signer = Signer('SHA-256/ECDSA')
        ..init(true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(privateKey), secureRandom));
      ECSignature signature = signer.generateSignature(Uint8List.fromList(messageHash)) as ECSignature;

      String signatureBase64 = base64Encode(
        bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32)
      );
      final fullUrl = '$baseUrl/swap_tokens';

      final Map<String, dynamic> payload = {
        'token': token,
        'nonce': nonceBase64,
        'signature': signatureBase64,
        'price': _btcZarPrice.toString(),
        'type': _isSwapped ? 'zarp_to_btc' : 'btc_to_zarp',
        'zarp_amount': _zarpController.text,
        'btc_amount': _btcController.text,
      };

      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        // Navigate to logged_in_home on success
        Navigator.pushReplacementNamed(context, '/logged_in_home');
      } else {
        setState(() => _errorMessage = "Swap failed: ${response.body}");
      }
    } catch (e) {
      setState(() => _errorMessage = "Error performing swap: $e");
    }
  }

  Future<void> _showSwapConfirmationDialog() async {
    if (_btcController.text.isEmpty || _zarpController.text.isEmpty) {
      setState(() => _errorMessage = "Please enter amounts to swap");
      return;
    }

    await _fetchPrice();
    
    if (_btcZarPrice > 0) {
      _updateConversion(_btcController, _zarpController);

      String fromAmount = _isSwapped ? _zarpController.text : _btcController.text;
      String toAmount = _isSwapped ? _btcController.text : _zarpController.text;
      String fromCurrency = _isSwapped ? 'ZARp' : 'BTC (SATS)';
      String toCurrency = _isSwapped ? 'BTC (SATS)' : 'ZARp';

      showDialog(
        context: context,
        builder: (BuildContext context) {
          Timer(Duration(seconds: 60), () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text(
              'Confirm your swap',
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Swapping: $fromAmount $fromCurrency',
                  style: TextStyle(color: Colors.white),
                ),
                Text(
                  'Receiving: $toAmount $toCurrency',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Show loading dialog
                    showDialog(
                      context: context,
                      barrierDismissible: false, // Prevents dismissal
                      builder: (BuildContext context) {
                        return Dialog(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE98B38)),
                            ),
                          ),
                        );
                      },
                    );
                    
                    // Perform swap and wait for response
                    await _performSwap();
                    
                    // Close loading dialog after response
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFE98B38),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: Text('Confirm Swap'),
                ),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  void dispose() {
    _btcController.dispose();
    _zarpController.dispose();
    _priceUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: null,
      ),
      body: Container(
        color: Colors.black,
        child: SingleChildScrollView(
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20),
                Text(
                  'Your Balances',
                  style: TextStyle(
                    fontSize: 26,
                    color: Color(0xFFE98B38),
                    fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                Container(
                  color: Colors.grey[900],
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/zarp.png',
                            width: 24,
                            height: 24,
                          ),
                          SizedBox(width: 10),
                          Text(
                            "ZARp",
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ],
                      ),
                      Text(
                        '${widget.zarpBalance} ZAR',
                        style: TextStyle(
                          color: Color(0xFFE98B38),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: Colors.white),
                Container(
                  color: Colors.grey[900],
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/btc.png',
                            width: 24,
                            height: 24,
                          ),
                          SizedBox(width: 10),
                          Text(
                            "BTC",
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${widget.satsBalance} SATS',
                            style: TextStyle(
                              color: Color(0xFFE98B38),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${widget.zarBalance} ZAR',
                            style: TextStyle(
                              color: Color(0xFFE98B38),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                Center(
                  child: Text(
                    'Swap',
                    style: TextStyle(
                      fontSize: 26,
                      color: Color(0xFFE98B38),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        Text(
                          _isSwapped ? 'ZARp' : 'BTC (SATS)',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: _isSwapped ? _zarpController : _btcController,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.grey[800],
                              border: OutlineInputBorder(),
                              hintStyle: TextStyle(color: Colors.grey),
                            ),
                            style: TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.swap_horiz, color: Colors.white),
                      onPressed: _swapCurrencies,
                    ),
                    Column(
                      children: [
                        Text(
                          _isSwapped ? 'BTC (SATS)' : 'ZARp',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: _isSwapped ? _btcController : _zarpController,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.grey[800],
                              border: OutlineInputBorder(),
                              hintStyle: TextStyle(color: Colors.grey),
                            ),
                            style: TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 10),
                if (_errorMessage != null)
                  Center(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: _errorMessage!.contains("successfully") ? Colors.green : Colors.red, fontSize: 14),
                    ),
                  ),
                SizedBox(height: 10),
                Center(
                  child: ElevatedButton(
                    onPressed: _showSwapConfirmationDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFE98B38),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      textStyle: TextStyle(fontSize: 18),
                    ),
                    child: Text('Swap'),
                  ),
                ),
                SizedBox(height: 40),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40.0),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/history_page');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white,
                          width: 1.0,
                        ),
                      ),
                      child: Text('History'),
                    ),
                  ),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}