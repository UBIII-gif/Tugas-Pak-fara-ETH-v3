import 'package:flutter_dotenv/flutter_dotenv.dart';

class BlockchainConfig {
  BlockchainConfig._();

  static Future<void> muat() => dotenv.load(fileName: 'env.txt');

  static String get rpcUrl => _wajib('RPC_URL');
  static String get contractAddress => _wajib('CONTRACT_ADDRESS');
  static String get reownProjectId => _wajib('REOWN_PROJECT_ID');

  static int get chainId =>
      int.tryParse(dotenv.env['CHAIN_ID']?.trim() ?? '') ?? 11155111;

  static const String _etherscan = 'https://sepolia.etherscan.io';
  static String urlTransaksi(String txHash) => '$_etherscan/tx/$txHash';

  static String _wajib(String kunci) {
    final nilai = dotenv.env[kunci]?.trim();
    if (nilai == null || nilai.isEmpty) {
      throw StateError('Variabel $kunci belum diisi di file env.txt');
    }
    return nilai;
  }
}