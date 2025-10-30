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
import 'withdraw_zarp.dart';
import 'balances.dart';
import 'logged_in_home.dart';
import 'buy_page.dart';
import 'send.dart'; // Import the SendPage
import 'dart:ui' show ImageFilter;

// Colors + text
class AppColors {
  static const bg = Colors.black;
  static const card = Color(0xFF101010);
  static const border = Color(0x14FFFFFF); // 8% white
  static const accent = Color(0xFFFF9500);
  static const accentSoft = Color(0xFFFFB866);
  static const text = Colors.white;
  static const subtext = Color(0xFF9A9A9A);
}
class AppText {
  static const label = TextStyle(fontSize: 14, color: AppColors.subtext, fontWeight: FontWeight.w600);
  static const headline = TextStyle(fontSize: 36, color: AppColors.text, fontWeight: FontWeight.w800, height: 1.1);
  static const sub = TextStyle(fontSize: 14, color: AppColors.subtext);
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
// Glass card
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.card.withOpacity(.85),
            border: Border.all(color: AppColors.border),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.5), blurRadius: 16, offset: const Offset(0, 10))],
          ),
          child: child,
        ),
      ),
    );
  }
}

// Pill action (outline + glow)
class PillActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const PillActionButton({super.key, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(.5), width: 1),
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF141414), Color(0xFF0A0A0A)],
          ),
        ),
        child: Text(label, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// Asset row tile
class AssetRow extends StatelessWidget {
  final Widget leadingIcon;
  final String code;
  final String amount;
  final String fiat;
  const AssetRow({super.key, required this.leadingIcon, required this.code, required this.amount, required this.fiat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // Use min to shrink-wrap
        children: [
          leadingIcon,
          const SizedBox(width: 12),
          Flexible( // Use Flexible instead of Expanded
            fit: FlexFit.loose,
            child: Text(code, style: const TextStyle(fontSize: 18, color: AppColors.text)),
          ),
          const SizedBox(width: 12),
          Flexible(
            fit: FlexFit.loose,
            child: Text(amount, style: const TextStyle(fontSize: 16, color: AppColors.text), textAlign: TextAlign.center),
          ),
          const SizedBox(width: 12),
          Flexible(
            fit: FlexFit.loose,
            child: Text(fiat, style: const TextStyle(fontSize: 16, color: AppColors.text), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}


const String authTokenKey = 'auth_token';
const String private = 'private_key';

class FinancePage extends StatefulWidget {
  @override
  _FinancePageState createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  String satsBalance = '';
  String zarBalance = '';
  String zarpBalance = '';
  String usdtBalance = '';
  String usdtZARBalance = '';
  String totalBalance = '';
  String firstName = '';
  String usernameError = '';
  final baseUrl = dotenv.env['API_BASE_URL'];
  bool isLoadingTotal = true;
  bool isLoadingZarp = true;
  bool isLoadingUsdt = true;
  bool isLoadingBtc = true;
  bool isLoadingRandZarp = true;
  bool isLoadingRandUsdt = true;
  bool isLoadingRandBtc = true;
  int _selectedIndex = 2; // Set to Finance tab

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

  TextEditingController usernameController = TextEditingController();
  GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _fetchBalance();
    FlutterCryptography.enable();
  }

  Future<void> _fetchBalance() async {
    setState(() {
      isLoadingTotal = true;
      isLoadingZarp = true;
      isLoadingUsdt = true;
      isLoadingBtc = true;
      isLoadingRandZarp = true;
      isLoadingRandUsdt = true;
      isLoadingRandBtc = true;
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (privateKeyBase64 == null || token == null) {
      setState(() {
        isLoadingTotal = false;
        isLoadingZarp = false;
        isLoadingUsdt = false;
        isLoadingBtc = false;
        isLoadingRandZarp = false;
        isLoadingRandUsdt = false;
        isLoadingRandBtc = false;
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
      double zarValue = double.parse(data['zar_balance'].toString());
      double zarpValue = double.parse(data['zarp_balance'].toString());
      double usdtValue = double.parse(data['usdt_balance'].toString());
      double usdtZARValue = double.parse(data['usdt_zar_balance'].toString());
      double totalValue = zarValue + zarpValue + usdtZARValue;

      setState(() {
        satsBalance = data['sats_balance'].toString();
        zarBalance = zarValue.toStringAsFixed(2);
        zarpBalance = zarpValue.toStringAsFixed(2);
        usdtBalance = usdtValue.toStringAsFixed(2);
        usdtZARBalance = usdtZARValue.toStringAsFixed(2);
        totalBalance = totalValue.toStringAsFixed(2);
        firstName = data['first_name'] ?? '';
        isLoadingTotal = false;
        isLoadingZarp = false;
        isLoadingUsdt = false;
        isLoadingBtc = false;
        isLoadingRandZarp = false;
        isLoadingRandUsdt = false;
        isLoadingRandBtc = false;
      });
    } else {
      setState(() {
        isLoadingTotal = false;
        isLoadingZarp = false;
        isLoadingUsdt = false;
        isLoadingBtc = false;
        isLoadingRandZarp = false;
        isLoadingRandUsdt = false;
        isLoadingRandBtc = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    await _fetchBalance();
    await Future.delayed(Duration(seconds: 1));
  }

  void _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.remove(authTokenKey);
    prefs.remove(private);

    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  Future<void> _logoutPostRequest() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? privateKeyBase64 = prefs.getString('private_key');
    String? token = prefs.getString('auth_token');

    if (privateKeyBase64 == null || token == null) {
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

    final apiUrl = '$baseUrl/logout';

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
      _logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text(
            'Finance',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: _handleRefresh,
          child: Container(
            color: Colors.black,
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width,
                ),
                child: Column(
                  children: [
                    // Greeting
                    const SizedBox(height: 8),
                    Text(
                      firstName.isNotEmpty ? 'Hello $firstName!' : 'Hello!',
                      style: const TextStyle(
                          fontSize: 20,
                          color: AppColors.text,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    // Balance card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GlassCard(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Balance', style: AppText.label),
                            const SizedBox(height: 6),
                            isLoadingTotal
                                ? const LinearProgressIndicator(
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(AppColors.accent),
                                    backgroundColor: Colors.white12,
                                    minHeight: 3,
                                  )
                                : ShaderMask(
                                    shaderCallback: (r) => const LinearGradient(
                                      colors: [AppColors.accent, AppColors.accentSoft],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ).createShader(r),
                                    child: Text('R$totalBalance',
                                        style: AppText.headline),
                                  ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40), // Increased spacer
                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 360;

                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PillActionButton(
                                  label: 'Cash In',
                                  onTap: () =>
                                      Navigator.pushNamed(context, '/receive_zarp'),
                                ),
                                const SizedBox(height: 12),
                                PillActionButton(
                                  label: 'Cash Out',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => WithdrawZarpPage()),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                PillActionButton(
                                  label: 'Swap',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BalancesPage(
                                        satsBalance: satsBalance,
                                        zarBalance: zarBalance,
                                        zarpBalance: zarpBalance,
                                        usdtBalance: usdtBalance,
                                        usdtZarBalance: usdtZARBalance,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                fit: FlexFit.loose,
                                child: PillActionButton(
                                  label: 'Cash In',
                                  onTap: () =>
                                      Navigator.pushNamed(context, '/receive_zarp'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                fit: FlexFit.loose,
                                child: PillActionButton(
                                  label: 'Cash Out',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => WithdrawZarpPage()),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                fit: FlexFit.loose,
                                child: PillActionButton(
                                  label: 'Swap',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BalancesPage(
                                        satsBalance: satsBalance,
                                        zarBalance: zarBalance,
                                        zarpBalance: zarpBalance,
                                        usdtBalance: usdtBalance,
                                        usdtZarBalance: usdtZARBalance,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Asset rows with header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const SizedBox(width: 36), // Space for leadingIcon
                              Flexible(
                                fit: FlexFit.loose,
                                child: Container(), // Empty space for code column
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                fit: FlexFit.loose,
                                child: Text(
                                  'Asset Value',
                                  style: AppText.label,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                fit: FlexFit.loose,
                                child: Text(
                                  'Rand Value',
                                  style: AppText.label,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          AssetRow(
                            leadingIcon:
                                Image.asset('assets/zarp.png', width: 24, height: 24),
                            code: 'ZARP',
                            amount: isLoadingZarp ? '—' : zarpBalance,
                            fiat: isLoadingRandZarp ? '—' : 'R$zarpBalance',
                          ),
                          const SizedBox(height: 12),
                          AssetRow(
                            leadingIcon:
                                Image.asset('assets/usdt.png', width: 24, height: 24),
                            code: 'USDT',
                            amount: isLoadingUsdt ? '—' : usdtBalance,
                            fiat: isLoadingRandUsdt ? '—' : 'R$usdtZARBalance',
                          ),
                          const SizedBox(height: 12),
                          AssetRow(
                            leadingIcon:
                                Image.asset('assets/btc.png', width: 24, height: 24),
                            code: 'BTC',
                            amount: isLoadingBtc
                                ? '—'
                                : (satsBalance.isNotEmpty
                                    ? (double.parse(satsBalance) / 100000000)
                                        .toStringAsFixed(6)
                                    : '0.000000'),
                            fiat: isLoadingRandBtc ? '—' : 'R$zarBalance',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Additional action buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          PillActionButton(
                            label: 'Receive Crypto',
                            onTap: () => Navigator.pushNamed(context, '/receive'),
                          ),
                          const SizedBox(height: 20), // Increased spacing
                          PillActionButton(
                            label: 'Send Crypto',
                            onTap: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => SendPage()));
                            },
                          ),
                          const SizedBox(height: 20), // Increased spacing
                          PillActionButton(
                            label: 'Logout',
                            onTap: _logoutPostRequest,
                          ),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: floatingBlurNav(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() => _selectedIndex = index);
            if (index == 0) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => LoggedInHomePage()),
                (r) => false,
              );
            } else if (index == 1) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => BuyPage()),
                (r) => false,
              );
            }
          },
        ),
      ),
    );
  }
}