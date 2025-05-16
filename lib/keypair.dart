import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:pointycastle/export.dart';

class ECDSAKeyGenerator {
  static Map<String, String> generateECDSAP256KeyPair() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    
    // Generate secure random seed
    final seed = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seed)));

    final keyGenerator = ECKeyGenerator();
    final domainParams = ECDomainParameters('secp256r1'); // Correct curve name

    final keyParams = ParametersWithRandom(
      ECKeyGeneratorParameters(domainParams),
      secureRandom,
    );

    keyGenerator.init(keyParams);
    final pair = keyGenerator.generateKeyPair();

    final publicKey = pair.publicKey as ECPublicKey;
    final privateKey = pair.privateKey as ECPrivateKey;

    // ✅ Correct BigInt to 32-byte big-endian array (no reversal)
    Uint8List bigIntToBytes(BigInt value) {
      final hexStr = value.toRadixString(16).padLeft(64, '0'); // Ensure 32-byte length (64 hex chars)
      final byteList = List<int>.generate(32, (i) => int.parse(hexStr.substring(i * 2, i * 2 + 2), radix: 16));
      return Uint8List.fromList(byteList); // Big-endian by default
    }


    // Convert to Base64
    return {
      'publicKeyX': base64Encode(bigIntToBytes(publicKey.Q!.x!.toBigInteger()!)),
      'publicKeyY': base64Encode(bigIntToBytes(publicKey.Q!.y!.toBigInteger()!)),
      'privateKey': base64Encode(bigIntToBytes(privateKey.d!)),
    };

  }
}