import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pointycastle/export.dart';

/// What the server is told about this phone when it asks to be registered. No MAC address or IMEI: they are not available to apps
/// any more and a person can change them; identity is the key pair below.
class DeviceFacts {
  const DeviceFacts({required this.uuid, required this.publicKey, this.platform = 'android', this.name, this.manufacturer, this.model, this.osName, this.osVersion, this.appVersion});

  final String uuid;
  final String publicKey;
  final String platform;
  final String? name;
  final String? manufacturer;
  final String? model;
  final String? osName;
  final String? osVersion;
  final String? appVersion;
}

/// Where the phone is, as the phone reports it (the server records it and, for an office that asks, compares it; it is a hint, never proof).
class PhonePlace {
  const PhonePlace({required this.latitude, required this.longitude, this.accuracy, this.at, this.mocked = false});

  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime? at;

  /// The phone itself says this location was faked (a mock-location app).
  final bool mocked;
}

/// This phone's identity for attendance: a private key made on it and never sent anywhere, the public half given to the server once
/// (and approved by an administrator), and the signing of each short-lived challenge. A fake replaces it in tests.
abstract class DeviceIdentity {
  /// Make the key pair on first use and return what the server needs to register this phone.
  Future<DeviceFacts> facts();

  /// This phone's id (stable while the app stays installed), without making a key.
  Future<String> uuid();

  /// ES256 over [payload]: base64 of the ASN.1 DER signature.
  Future<String> sign(final String payload);

  /// Where the phone is now, or null (permission refused, location off, no fix in time).
  Future<PhonePlace?> place();
}

/// The real one. The private key (a P-256 number) is kept in the platform's secure storage (Android Keystore-protected on Android,
/// Keychain on iOS). It is not a hardware-bound key: it cannot be exported by the app, but a rooted phone could read it, which is why the
/// administrator's approval of each device and the log stay in place.
class SecureDeviceIdentity implements DeviceIdentity {
  SecureDeviceIdentity({final FlutterSecureStorage? storage}) : _store = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _store;
  static const String _kPriv = 'att_priv_d';
  static const String _kUuid = 'att_uuid';

  static final ECDomainParameters _curve = ECCurve_secp256r1();

  static SecureRandom _random() {
    final FortunaRandom r = FortunaRandom();
    final Random seed = Random.secure();
    r.seed(KeyParameter(Uint8List.fromList(List<int>.generate(32, (_) => seed.nextInt(256)))));

    return r;
  }

  @override
  Future<String> uuid() async {
    String? id = await _store.read(key: _kUuid);
    if (id == null || id.length < 16) {
      final Random r = Random.secure();
      id = List<String>.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _store.write(key: _kUuid, value: id);
    }

    return id;
  }

  Future<ECPrivateKey> _private() async {
    final String? d = await _store.read(key: _kPriv);
    if (d != null && d.isNotEmpty) return ECPrivateKey(BigInt.parse(d, radix: 16), _curve);
    final AsymmetricKeyPair<PublicKey, PrivateKey> pair = (ECKeyGenerator()..init(ParametersWithRandom<ECKeyGeneratorParameters>(ECKeyGeneratorParameters(_curve), _random()))).generateKeyPair();
    final ECPrivateKey key = pair.privateKey as ECPrivateKey;
    await _store.write(key: _kPriv, value: key.d!.toRadixString(16));

    return key;
  }

  @override
  Future<DeviceFacts> facts() async {
    final ECPrivateKey key = await _private();
    final String id = await uuid();
    String? manufacturer, model, osName, osVersion, name;
    String platform = 'android';
    try {
      final DeviceInfoPlugin info = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final IosDeviceInfo i = await info.iosInfo;
        platform = 'ios';
        manufacturer = 'Apple';
        model = i.utsname.machine;
        name = i.name;
        osName = i.systemName;
        osVersion = i.systemVersion;
      } else {
        final AndroidDeviceInfo a = await info.androidInfo;
        manufacturer = a.manufacturer;
        model = a.model;
        name = '${a.manufacturer} ${a.model}';
        osName = 'Android';
        osVersion = a.version.release;
      }
    } on Exception {
      // The facts are for the administrator's eyes; the key is what identifies the phone.
    }
    String? app;
    try {
      final PackageInfo p = await PackageInfo.fromPlatform();
      app = '${p.version}+${p.buildNumber}';
    } on Exception {
      app = null;
    }

    return DeviceFacts(uuid: id, publicKey: _publicKeyOf(key), platform: platform, name: name, manufacturer: manufacturer, model: model, osName: osName, osVersion: osVersion, appVersion: app);
  }

  /// The public key as base64 of the SubjectPublicKeyInfo (the form every server library reads).
  String _publicKeyOf(final ECPrivateKey key) {
    final ECPoint q = (_curve.G * key.d)!;
    final Uint8List x = _fixed(q.x!.toBigInteger()!), y = _fixed(q.y!.toBigInteger()!);
    const List<int> header = <int>[0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00, 0x04];

    return base64Encode(<int>[...header, ...x, ...y]);
  }

  @override
  Future<String> sign(final String payload) async {
    final ECPrivateKey key = await _private();
    final ECDSASigner signer = ECDSASigner(SHA256Digest())..init(true, ParametersWithRandom<PrivateKeyParameter<ECPrivateKey>>(PrivateKeyParameter<ECPrivateKey>(key), _random()));
    final ECSignature sig = signer.generateSignature(Uint8List.fromList(utf8.encode(payload))) as ECSignature;

    return base64Encode(derSignature(sig.r, sig.s));
  }

  @override
  Future<PhonePlace?> place() => readPhonePlace();

  static Uint8List _fixed(final BigInt v) {
    final Uint8List out = Uint8List(32);
    BigInt n = v;
    for (int i = 31; i >= 0; i--) {
      out[i] = (n & BigInt.from(0xff)).toInt();
      n = n >> 8;
    }

    return out;
  }
}

/// Where the phone is now (asks for the location permission if it must), or null: permission refused, location off, or no fix in time.
Future<PhonePlace?> readPhonePlace() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    final Position pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)));

    return PhonePlace(latitude: pos.latitude, longitude: pos.longitude, accuracy: pos.accuracy, at: pos.timestamp, mocked: pos.isMocked);
  } on Exception {
    return null;
  }
}

/// ECDSA (r, s) as the ASN.1 DER sequence the server's `openssl_verify` reads.
@visibleForTesting
Uint8List derSignature(final BigInt r, final BigInt s) {
  List<int> integer(final BigInt v) {
    List<int> b = <int>[];
    BigInt n = v;
    if (n == BigInt.zero) b = <int>[0];
    while (n > BigInt.zero) {
      b.insert(0, (n & BigInt.from(0xff)).toInt());
      n = n >> 8;
    }
    if (b.first & 0x80 != 0) b.insert(0, 0);

    return <int>[0x02, b.length, ...b];
  }

  final List<int> body = <int>[...integer(r), ...integer(s)];

  return Uint8List.fromList(<int>[0x30, body.length, ...body]);
}
