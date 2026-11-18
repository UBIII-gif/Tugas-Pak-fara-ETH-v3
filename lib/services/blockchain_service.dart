import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:reown_appkit/reown_appkit.dart';
import 'package:web3dart/crypto.dart';

import '../config/blockchain_config.dart';
import '../models/sertifikat.dart';

class TransaksiException implements Exception {
  TransaksiException(this.pesan);
  final String pesan;

  @override
  String toString() => pesan;
}

class BlockchainService extends ChangeNotifier {
  BlockchainService._(
    Web3Client client,
    DeployedContract contract,
  )   : _client = client,
        _contract = contract,
        _fnJumlah = contract.function('jumlahSertifikat'),
        _fnAmbil = contract.function('ambilSertifikat'),
        _fnTerbitkan = contract.function('terbitkanSertifikat'),
        _fnEdit = contract.function('editNamaKegiatan'),
        _fnCabut = contract.function('cabutSertifikat'),
        _fnVerifikasi = _cariFungsi(contract, 'verifikasiHash'),
        _evTerbit = contract.event('SertifikatDiterbitkan'),
        _evEdit = contract.event('SertifikatDiedit'),
        _evCabut = contract.event('SertifikatDicabut');

  final Web3Client _client;
  final DeployedContract _contract;
  ReownAppKitModal? _appKitModal;
  String? reownError;

  final ContractFunction _fnJumlah;
  final ContractFunction _fnAmbil;
  final ContractFunction _fnTerbitkan;
  final ContractFunction _fnEdit;
  final ContractFunction _fnCabut;
  final ContractFunction? _fnVerifikasi;
  final ContractEvent _evTerbit;
  final ContractEvent _evEdit;
  final ContractEvent _evCabut;

  static const int _ukuranBatch = 5;

  static Future<BlockchainService> buat() async {
    final abiJson = await rootBundle.loadString('assets/abi/SertifikatKegiatan.json');
    final contract = DeployedContract(
      ContractAbi.fromJson(abiJson, 'SertifikatKegiatan'),
      EthereumAddress.fromHex(BlockchainConfig.contractAddress),
    );
    final client = Web3Client(BlockchainConfig.rpcUrl, http.Client());
    return BlockchainService._(client, contract);
  }

  Future<void> initReown(BuildContext context) async {
    if (_appKitModal != null) return;

    try {
      ReownAppKitModalNetworks.addSupportedNetworks('eip155', [
        ReownAppKitModalNetworkInfo(
          name: 'Sepolia',
          chainId: '${BlockchainConfig.chainId}',
          currency: 'ETH',
          rpcUrl: BlockchainConfig.rpcUrl,
          explorerUrl: 'https://sepolia.etherscan.io',
        ),
      ]);

      final modal = ReownAppKitModal(
        context: context,
        projectId: BlockchainConfig.reownProjectId,
        metadata: const PairingMetadata(
          name: 'Sertifikat Kegiatan dApp',
          description: 'Penerbitan & Verifikasi Sertifikat Digital di Sepolia',
          url: 'https://sertifikat-dapp.local',
          icons: ['https://walletconnect.com/walletconnect-logo.png'],
        ),
      );

      modal.addListener(notifyListeners);
      _appKitModal = modal;
      notifyListeners();

      await modal.init();
      reownError = null;
      notifyListeners();
    } catch (e) {
      reownError = e.toString();
      debugPrint('Gagal init Reown: $e');
      notifyListeners();
    }
  }

  ReownAppKitModal? get appKitModal => _appKitModal;
  bool get isConnected => _appKitModal?.isConnected ?? false;

  EthereumAddress? get alamatWallet {
    final modal = _appKitModal;
    if (modal == null || !modal.isConnected || modal.session == null) return null;
    final addrStr = modal.session!.getAddress('eip155');
    if (addrStr == null || addrStr.isEmpty) return null;
    return EthereumAddress.fromHex(addrStr);
  }

  static ContractFunction? _cariFungsi(DeployedContract c, String nama) {
    for (final f in c.abi.functions) {
      if (f.name == nama) return f;
    }
    return null;
  }

  @override
  void dispose() {
    _appKitModal?.removeListener(notifyListeners);
    _client.dispose();
    super.dispose();
  }

  Future<double?> ambilSaldoEth() async {
    final wallet = alamatWallet;
    if (wallet == null) return null;
    final saldoWei = await _client.getBalance(wallet);
    return saldoWei.getValueInUnit(EtherUnit.ether);
  }

  Future<int> jumlahSertifikat() async {
    final r = await _client.call(contract: _contract, function: _fnJumlah, params: []);
    return (r.first as BigInt).toInt();
  }

  Future<Sertifikat> ambilSertifikat(int id) async {
    final r = await _client.call(
      contract: _contract,
      function: _fnAmbil,
      params: [BigInt.from(id)],
    );
    return Sertifikat(
      id: id,
      hashBerkas: r[0] as String,
      namaKegiatan: r[1] as String,
      namaPenerbit: r[2] as String,
      waktuTerbit: DateTime.fromMillisecondsSinceEpoch((r[3] as BigInt).toInt() * 1000),
      alamatPenerbit: r[4] as EthereumAddress,
      valid: r[5] as bool,
    );
  }

  Future<List<Sertifikat>> ambilSemua() async {
    final total = await jumlahSertifikat();
    if (total == 0) return [];

    final hasil = <Sertifikat>[];
    for (var awal = total - 1; awal >= 0; awal -= _ukuranBatch) {
      final akhir = max(0, awal - _ukuranBatch + 1);
      hasil.addAll(await Future.wait([
        for (var id = awal; id >= akhir; id--) ambilSertifikat(id),
      ]));
    }
    return hasil;
  }

  Future<HasilVerifikasi> verifikasiHash(String hashBerkas) async {
    final hash = hashBerkas.trim();
    final fn = _fnVerifikasi;

    if (fn != null) {
      final r = await _client.call(contract: _contract, function: fn, params: [hash]);
      return HasilVerifikasi(
        ditemukan: r[0] as bool,
        id: (r[1] as BigInt).toInt(),
        masihValid: r[2] as bool,
      );
    }

    final total = await jumlahSertifikat();
    if (total == 0) {
      return const HasilVerifikasi(ditemukan: false, id: -1, masihValid: false);
    }

    for (var awal = total - 1; awal >= 0; awal -= _ukuranBatch) {
      final akhir = max(0, awal - _ukuranBatch + 1);
      final batch = await Future.wait([
        for (var id = awal; id >= akhir; id--) ambilSertifikat(id),
      ]);
      for (final s in batch) {
        if (s.hashBerkas.toLowerCase() == hash.toLowerCase()) {
          return HasilVerifikasi(ditemukan: true, id: s.id, masihValid: s.valid);
        }
      }
    }
    return const HasilVerifikasi(ditemukan: false, id: -1, masihValid: false);
  }

  Future<String> terbitkanSertifikat({
    required String hashBerkas,
    required String namaKegiatan,
    required String namaPenerbit,
  }) =>
      _kirimViaReown(_fnTerbitkan, [hashBerkas, namaKegiatan, namaPenerbit]);

  Future<String> editNamaKegiatan({
    required int id,
    required String namaKegiatanBaru,
  }) =>
      _kirimViaReown(_fnEdit, [BigInt.from(id), namaKegiatanBaru]);

  Future<String> cabutSertifikat(int id) =>
      _kirimViaReown(_fnCabut, [BigInt.from(id)]);

  Future<String> _kirimViaReown(ContractFunction fn, List<dynamic> parameter) async {
    final modal = _appKitModal;
    final pengirim = alamatWallet;
    if (modal == null || !modal.isConnected || modal.session == null || pengirim == null) {
      throw TransaksiException('Hubungkan wallet terlebih dahulu melalui tombol Connect Wallet.');
    }

    final dataHex = bytesToHex(fn.encodeCall(parameter), include0x: true);
    final chainNamespace = 'eip155:${BlockchainConfig.chainId}';

    final hasil = await modal.request(
      topic: modal.session!.topic,
      chainId: chainNamespace,
      request: SessionRequestParams(
        method: 'eth_sendTransaction',
        params: [
          {
            'from': pengirim.hexEip55,
            'to': BlockchainConfig.contractAddress,
            'data': dataHex,
          }
        ],
      ),
    );

    if (hasil == null) {
      throw TransaksiException('Transaksi dibatalkan di wallet.');
    }
    return hasil.toString();
  }

  Future<TransactionReceipt> tungguKonfirmasi(
    String txHash, {
    Duration batasWaktu = const Duration(minutes: 3),
  }) async {
    final batas = DateTime.now().add(batasWaktu);
    while (DateTime.now().isBefore(batas)) {
      final receipt = await _client.getTransactionReceipt(txHash);
      if (receipt != null) {
        if (receipt.status == false) {
          throw TransaksiException('Transaksi masuk blok tetapi ditolak oleh smart contract.');
        }
        return receipt;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw TransaksiException(
      'Transaksi belum terkonfirmasi dalam ${batasWaktu.inMinutes} menit. '
      'Cek statusnya di Etherscan dengan hash:\n$txHash',
    );
  }

  Stream<String> pantauPerubahan() {
    final controller = StreamController<String>();
    final langganan = <StreamSubscription<FilterEvent>>[];

    controller.onListen = () {
      langganan.add(_client
          .events(FilterOptions.events(
            contract: _contract,
            event: _evTerbit,
            fromBlock: const BlockNum.current(),
          ))
          .listen((_) => controller.add('terbit'), onError: (_) {}));
      langganan.add(_client
          .events(FilterOptions.events(
            contract: _contract,
            event: _evEdit,
            fromBlock: const BlockNum.current(),
          ))
          .listen((_) => controller.add('edit'), onError: (_) {}));
      langganan.add(_client
          .events(FilterOptions.events(
            contract: _contract,
            event: _evCabut,
            fromBlock: const BlockNum.current(),
          ))
          .listen((_) => controller.add('cabut'), onError: (_) {}));
    };
    controller.onCancel = () async {
      for (final s in langganan) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  static String pesanError(Object e) {
    if (e is TransaksiException) return e.pesan;
    if (e is JsonRpcError) {
      final pesan = (e.message ?? '').toLowerCase();
      if (pesan.contains('rejected') || pesan.contains('denied')) {
        return 'Permintaan tanda tangan ditolak di aplikasi wallet.';
      }
      return 'Wallet error (${e.code}):${e.message}';
    }
    if (e is TimeoutException) return 'Permintaan ke jaringan melebihi batas waktu. Coba lagi.';
    if (e is RPCError) {
      final alasan = _alasanRevert(e.data);
      if (alasan != null) return 'Ditolak smart contract: $alasan';
      final pesan = e.message.toLowerCase();
      if (pesan.contains('insufficient funds')) {
        return 'Saldo ETH Sepolia di wallet tidak cukup untuk membayar gas.';
      }
      if (pesan.contains('execution reverted')) {
        return 'Ditolak smart contract: ${e.message.replaceFirst('execution reverted:', '').trim()}';
      }
      return 'Error RPC (${e.errorCode}):${e.message}';
    }
    if (e is http.ClientException) {
      return 'Tidak ada koneksi internet atau RPC tidak bisa dijangkau.';
    }
    if (e is StateError) return e.message;
    return e.toString();
  }

  static String? _alasanRevert(dynamic data) {
    if (data is! String || !data.startsWith('0x08c379a0')) return null;
    try {
      final bytes = hexToBytes(data);
      final panjang = bytesToUnsignedInt(bytes.sublist(36, 68)).toInt();
      return utf8.decode(bytes.sublist(68, 68 + panjang));
    } catch (_) {
      return null;
    }
  }
}