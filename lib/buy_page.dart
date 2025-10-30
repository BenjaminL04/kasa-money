import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/random/fortuna_random.dart' as pc;
import 'dart:typed_data';
import 'dart:math';
import 'logged_in_home.dart';
import 'buy_electricity.dart';
import 'package:pointycastle/digests/sha256.dart' as pc;
import 'package:pointycastle/signers/ecdsa_signer.dart' as pc;
import 'package:pointycastle/asymmetric/api.dart' as pc;
import 'package:pointycastle/ecc/api.dart' as pc;
import 'package:pointycastle/ecc/curves/secp256r1.dart' as pc;
import 'finance_page.dart'; // Added import for FinancePage
import 'dart:ui' show ImageFilter;
import 'package:flutter/services.dart';

class ModernActionButton extends StatelessWidget {
  final String label;
  final String emoji;
  final VoidCallback onPressed;

  const ModernActionButton({
    super.key,
    required this.label,
    required this.emoji,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => HapticFeedback.lightImpact(),
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Glass / blur
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(height: 64),
            ),
            // Button body
            Container(
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF141414), Color(0xFF0A0A0A)],
                ),
                border: Border.all(color: Colors.white12, width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(.45), blurRadius: 16, offset: const Offset(0, 10)),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: emoji + label
                  Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: .2,
                        ),
                      ),
                    ],
                  ),
                  // Right: chevron with orange glow
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9500), Color(0xFFFFB866)],
                      ),
                    ),
                    child: const Icon(Icons.chevron_right, color: Colors.black, size: 22),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget floatingBlurNav({
  required int currentIndex,
  required ValueChanged<int> onTap,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.black.withOpacity(.6),
          elevation: 0,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: false,
          currentIndex: currentIndex,
          onTap: onTap,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.space_dashboard_outlined), label: 'Home'),
            BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart_outlined), label: 'Buy'),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined), label: 'Finance'),
          ],
        ),
      ),
    ),
  );
}



class BuyPage extends StatefulWidget {
  @override
  _BuyPageState createState() => _BuyPageState();
}

class _BuyPageState extends State<BuyPage> {
  int _selectedIndex = 1;

void _onItemTapped(int index) {
  setState(() {
    _selectedIndex = index;
  });
  if (index == 0) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => LoggedInHomePage()),
      (route) => false,
    );
  } else if (index == 2) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => FinancePage()),
      (route) => false,
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Buy'),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ModernActionButton(
                emoji: '📱',
                label: 'Buy Airtime',
                onPressed: _showAirtimeDialog,
              ),
              const SizedBox(height: 16),
              ModernActionButton(
                emoji: '⚡️',
                label: 'Buy Electricity',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => BuyElectricityPage()));
                },
              ),
              const SizedBox(height: 16),
              ModernActionButton(
                emoji: '📶',
                label: 'Buy Data Bundles',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => BundleSelectionPage()));
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: floatingBlurNav(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }

  void _showAirtimeDialog() {
    String _dropdownNetwork = 'p-vodacom';
    double _amount = 2.0;
    bool _buyForMyself = true;
    String? _sendToNumber;
    final List<String> airtimeNetworks = ['p-vodacom', 'p-mtn', 'p-cellc', 'p-telkom'];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: Text('Buy Airtime', style: TextStyle(color: Colors.white)),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
              minWidth: double.infinity,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setDialogState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        dropdownColor: Colors.black,
                        decoration: InputDecoration(
                          labelText: 'Network',
                          labelStyle: TextStyle(color: Colors.white),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                        ),
                        style: TextStyle(color: Colors.white),
                        value: _dropdownNetwork,
                        items: airtimeNetworks.map((net) {
                          return DropdownMenuItem(
                            value: net,
                            child: Text(net.replaceAll('p-', '').toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() => _dropdownNetwork = val!);
                        },
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Amount (R2 - R1000)',
                          labelStyle: TextStyle(color: Colors.white),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                        ),
                        initialValue: _amount.toStringAsFixed(2),
                        onChanged: (value) {
                          double amt = double.tryParse(value) ?? 2.0;
                          setDialogState(() => _amount = amt.clamp(2.0, 1000.0));
                        },
                      ),
                      SizedBox(height: 12),
                      CheckboxListTile(
                        value: _buyForMyself,
                        onChanged: (val) {
                          setDialogState(() => _buyForMyself = val ?? true);
                        },
                        title: Text("Buy for Myself", style: TextStyle(color: Colors.white)),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: Colors.white,
                        checkColor: Colors.black,
                      ),
                      if (!_buyForMyself)
                        TextFormField(
                          keyboardType: TextInputType.phone,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Enter number to send to',
                            labelStyle: TextStyle(color: Colors.white),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                          onChanged: (val) {
                            setDialogState(() => _sendToNumber = val);
                          },
                        ),
                      SizedBox(height: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () async {
                          if (!_buyForMyself && (_sendToNumber == null || _sendToNumber!.isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Please enter a phone number')),
                            );
                            return;
                          }
                          Navigator.pop(context);
                          String number = _buyForMyself ? 'own' : (_sendToNumber ?? '');
                          if (number.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Phone number not found for self-purchase')),
                            );
                            return;
                          }
                          try {
                            print('Initiating airtime purchase for number: $number');
                            await purchaseBundle(
                              _dropdownNetwork,
                              _amount,
                              number,
                            );
                          } catch (e) {
                            print('Airtime dialog purchase error: $e');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error initiating airtime purchase: ${e.toString()}')),
                            );
                          }
                        },
                        child: Text('Buy'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  pc.SecureRandom getSecureRandom() {
    final secureRandom = pc.FortunaRandom()
      ..seed(pc.KeyParameter(Uint8List.fromList(List.generate(32, (i) => Random.secure().nextInt(256)))));
    return secureRandom;
  }

  Uint8List bigIntToBytes(BigInt number, int byteLength) {
    final byteList = number.toRadixString(16).padLeft(byteLength * 2, '0');
    return Uint8List.fromList(List.generate(byteLength, (i) {
      return int.parse(byteList.substring(i * 2, i * 2 + 2), radix: 16);
    }));
  }

  Future<Map<String, String>> generateSignature() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (privateKeyBase64 == null || token == null) {
      throw Exception('Private key or token not found');
    }

    final nonce = List<int>.generate(16, (i) => Random.secure().nextInt(256));
    String nonceBase64 = base64Encode(nonce);
    String messageWithNonce = "$token:$nonceBase64";
    final messageHash = pc.SHA256Digest().process(utf8.encode(messageWithNonce));

    Uint8List privateKeyBytes = base64Decode(privateKeyBase64);
    BigInt privateKeyInt = BigInt.parse(
        privateKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16);

    final privateKey = pc.ECPrivateKey(privateKeyInt, pc.ECDomainParameters('secp256r1'));
    final secureRandom = getSecureRandom();

    final signer = pc.Signer('SHA-256/ECDSA')
      ..init(true, pc.ParametersWithRandom(pc.PrivateKeyParameter<pc.ECPrivateKey>(privateKey), secureRandom));

    pc.ECSignature signature = signer.generateSignature(Uint8List.fromList(messageHash)) as pc.ECSignature;
    String signatureBase64 = base64Encode(
      bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32)
    );

    return {
      'nonce': nonceBase64,
      'signature': signatureBase64,
      'token': token,
    };
  }

  Future<void> purchaseBundle(String network, double sellValue, String number) async {
    try {
      final authData = await generateSignature();
      final String networkPrefix = network;
      final response = await http.post(
        Uri.parse('https://db.btckhaya.com/purchase_bundle'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'network': networkPrefix,
          'sellValue': sellValue,
          'number': number,
          'token': authData['token'],
          'nonce': authData['nonce'],
          'signature': authData['signature'],
        }),
      );

      print('purchaseBundle response status: ${response.statusCode}');
      print('purchaseBundle response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bundle purchase successful: ${data['orderno']}')),
        );
      } else {
        throw Exception('Failed to purchase bundle: ${response.body}');
      }
    } catch (e) {
      print('Purchase bundle error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error purchasing bundle: ${e.toString()}')),
      );
      throw e;
    }
  }
}

class BundleSelectionPage extends StatefulWidget {
  @override
  _BundleSelectionPageState createState() => _BundleSelectionPageState();
}

class _BundleSelectionPageState extends State<BundleSelectionPage> {
  List<dynamic> _options = [];
  String _selectedNetwork = '';
  bool _buyForMyself = true;
  String? _sendToNumber;
  final List<String> networks = ['pd-vodacom', 'pd-mtn', 'pd-cellc', 'pd-telkom'];
  final Map<String, String> networkLogos = {
    'pd-vodacom': 'assets/vodacom_logo.png',
    'pd-mtn': 'assets/mtn_logo.png',
    'pd-cellc': 'assets/cellc_logo.png',
    'pd-telkom': 'assets/telkom_logo.png',
  };

  Future<void> fetchOptions(String network) async {
    try {
      final url = Uri.parse('https://db.btckhaya.com/airtime_options');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'networks': ['all'],
          'type': 'bundle'
        }),
      );

      print('fetchOptions response status: ${response.statusCode}');
      print('fetchOptions response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _selectedNetwork = network;
          _options = data[network] is List ? data[network] : [];
        });
      } else {
        setState(() {
          _options = [];
        });
        throw Exception('Failed to load options: ${response.body}');
      }
    } catch (e) {
      print('Fetch options error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching options: ${e.toString()}')),
      );
    }
  }

  Widget _buildNetworkButton(String name) {
    return ElevatedButton(
      onPressed: () => fetchOptions(name),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white10,
        foregroundColor: Colors.white,
        padding: EdgeInsets.all(20),
      ),
      child: Image.asset(
        networkLogos[name]!,
        height: 40,
        fit: BoxFit.contain,
      ),
    );
  }

  void _showBundleDialog(Map<String, dynamic> option) {
    _sendToNumber = null;
    _buyForMyself = true;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: Text('Confirm Bundle', style: TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bundle Details:',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Network: ${_selectedNetwork.replaceAll('pd-', '').toUpperCase()}',
                      style: TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Size: ${option['bundle_size']}',
                      style: TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Price: R${option['sellValue']}',
                      style: TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Type: ${option['bundle_type']}',
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 12),
                    CheckboxListTile(
                      value: _buyForMyself,
                      onChanged: (val) {
                        setDialogState(() => _buyForMyself = val ?? true);
                      },
                      title: Text("Buy for Myself", style: TextStyle(color: Colors.white)),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: Colors.white,
                      checkColor: Colors.black,
                    ),
                    if (!_buyForMyself)
                      TextFormField(
                        keyboardType: TextInputType.phone,
                        style: TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Enter number to send to',
                          labelStyle: TextStyle(color: Colors.white),
                          enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white)),
                        ),
                        onChanged: (val) {
                          setDialogState(() => _sendToNumber = val);
                        },
                      ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () async {
                        if (!_buyForMyself && (_sendToNumber == null || _sendToNumber!.isEmpty)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Please enter a phone number')),
                          );
                          return;
                        }
                        Navigator.pop(context);
                        String number = _buyForMyself ? 'own' : (_sendToNumber ?? '');
                        if (number.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Phone number not found for self-purchase')),
                          );
                          return;
                        }
                        try {
                          print('Initiating bundle purchase for number: $number');
                          await purchaseBundle(
                            _selectedNetwork,
                            double.parse(option['sellValue'].toString()),
                            number,
                          );
                        } catch (e) {
                          print('Bundle dialog purchase error: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error initiating bundle purchase: ${e.toString()}')),
                          );
                        }
                      },
                      child: Text('Confirm'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildOptionsList() {
    if (_options.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 20),
        Text(
          'Options for ${_selectedNetwork.replaceAll('pd-', '').toUpperCase()}:',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ..._options.map((option) {
          final bundle = option is String
              ? {'bundle_size': option, 'sellValue': 0.0, 'bundle_type': 'Unknown'}
              : option;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${bundle['bundle_size']} - R${bundle['sellValue']} (${bundle['bundle_type']})',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFE98B38),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _showBundleDialog(bundle),
                  child: Text('Buy'),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Select Bundle'),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bundles',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2,
                children: networks.map((n) => _buildNetworkButton(n)).toList(),
              ),
              SizedBox(height: 20),
              _buildOptionsList(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> purchaseBundle(String network, double sellValue, String number) async {
    try {
      final authData = await generateSignature();
      final String networkPrefix = network;
      final response = await http.post(
        Uri.parse('https://db.btckhaya.com/purchase_bundle'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'network': networkPrefix,
          'sellValue': sellValue,
          'number': number,
          'token': authData['token'],
          'nonce': authData['nonce'],
          'signature': authData['signature'],
        }),
      );

      print('purchaseBundle response status: ${response.statusCode}');
      print('purchaseBundle response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bundle purchase successful: ${data['orderno']}')),
        );
      } else {
        throw Exception('Failed to purchase bundle: ${response.body}');
      }
    } catch (e) {
      print('Purchase bundle error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error purchasing bundle: ${e.toString()}')),
      );
      throw e;
    }
  }

  pc.SecureRandom getSecureRandom() {
    final secureRandom = pc.FortunaRandom()
      ..seed(pc.KeyParameter(Uint8List.fromList(List.generate(32, (i) => Random.secure().nextInt(256)))));
    return secureRandom;
  }

  Uint8List bigIntToBytes(BigInt number, int byteLength) {
    final byteList = number.toRadixString(16).padLeft(byteLength * 2, '0');
    return Uint8List.fromList(List.generate(byteLength, (i) {
      return int.parse(byteList.substring(i * 2, i * 2 + 2), radix: 16);
    }));
  }

  Future<Map<String, String>> generateSignature() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (privateKeyBase64 == null || token == null) {
      throw Exception('Private key or token not found');
    }

    final nonce = List<int>.generate(16, (i) => Random.secure().nextInt(256));
    String nonceBase64 = base64Encode(nonce);
    String messageWithNonce = "$token:$nonceBase64";
    final messageHash = pc.SHA256Digest().process(utf8.encode(messageWithNonce));

    Uint8List privateKeyBytes = base64Decode(privateKeyBase64);
    BigInt privateKeyInt = BigInt.parse(
        privateKeyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16);

    final privateKey = pc.ECPrivateKey(privateKeyInt, pc.ECDomainParameters('secp256r1'));
    final secureRandom = getSecureRandom();

    final signer = pc.Signer('SHA-256/ECDSA')
      ..init(true, pc.ParametersWithRandom(pc.PrivateKeyParameter<pc.ECPrivateKey>(privateKey), secureRandom));

    pc.ECSignature signature = signer.generateSignature(Uint8List.fromList(messageHash)) as pc.ECSignature;
    String signatureBase64 = base64Encode(
      bigIntToBytes(signature.r, 32) + bigIntToBytes(signature.s, 32)
    );

    return {
      'nonce': nonceBase64,
      'signature': signatureBase64,
      'token': token,
    };
  }
}