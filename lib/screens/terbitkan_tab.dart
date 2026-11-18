import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/blockchain_service.dart';
import '../utils/format.dart';
import '../widgets/tx_dialog.dart';

class TerbitkanTab extends StatefulWidget {
  const TerbitkanTab({
    super.key,
    required this.service,
    required this.onBerhasil,
  });

  final BlockchainService service;
  final VoidCallback onBerhasil;

  @override
  State<TerbitkanTab> createState() => _TerbitkanTabState();
}

class _TerbitkanTabState extends State<TerbitkanTab> {
  final _formKey = GlobalKey<FormState>();
  final _namaKegiatanC = TextEditingController();
  final _namaPenerbitC = TextEditingController();

  String? _namaFile;
  String? _hashBerkas;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(_refresh);
    _namaKegiatanC.dispose();
    _namaPenerbitC.dispose();
    super.dispose();
  }

  Future<void> _pilihBerkas() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;

    final file = res.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final digest = sha256.convert(bytes).toString();
    setState(() {
      _namaFile = file.name;
      _hashBerkas = digest;
    });
  }

  Future<void> _kirim() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_hashBerkas == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih file sertifikat terlebih dahulu.')),
      );
      return;
    }

    final sukses = await jalankanTransaksi(
      context,
      service: widget.service,
      judul: 'Konfirmasi penerbitan di wallet...',
      kirim: () => widget.service.terbitkanSertifikat(
        hashBerkas: _hashBerkas!,
        namaKegiatan: _namaKegiatanC.text.trim(),
        namaPenerbit: _namaPenerbitC.text.trim(),
      ),
    );

    if (sukses && mounted) {
      _namaKegiatanC.clear();
      setState(() {
        _namaFile = null;
        _hashBerkas = null;
      });
      widget.onBerhasil();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final wallet = widget.service.alamatWallet;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  wallet == null ? Icons.link_off : Icons.account_balance_wallet,
                  color: wallet == null
                      ? tema.colorScheme.error
                      : tema.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Wallet Penerbit', style: tema.textTheme.labelMedium),
                      Text(
                        wallet == null
                            ? 'Belum terhubung (klik Connect Wallet di atas)'
                            : potongAlamat(wallet.hexEip55),
                        style: tema.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _pilihBerkas,
                icon: const Icon(Icons.upload_file),
                label: Text(_namaFile ?? 'Pilih berkas sertifikat (PDF / Gambar)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              if (_hashBerkas != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tema.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'SHA-256: $_hashBerkas',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _namaKegiatanC,
                decoration: const InputDecoration(
                  labelText: 'Nama kegiatan',
                  hintText: 'Contoh: Seminar Nasional Teknologi 2026',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _namaPenerbitC,
                decoration: const InputDecoration(
                  labelText: 'Nama institusi / penerbit',
                  hintText: 'Contoh: Jurusan Teknologi Informasi POLNES',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: wallet == null ? null : _kirim,
                icon: const Icon(Icons.send),
                label: Text(
                  wallet == null
                      ? 'Hubungkan wallet untuk menerbitkan'
                      : 'Terbitkan ke blockchain',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}