import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';

import '../models/sertifikat.dart';
import '../services/blockchain_service.dart';
import '../utils/format.dart';
import '../widgets/sertifikat_card.dart';
import '../widgets/tx_dialog.dart';
import 'terbitkan_tab.dart';
import 'verifikasi_tab.dart';

enum FilterDaftar {
  semua('Semua'),
  valid('Valid'),
  dicabut('Dicabut'),
  milikku('Wallet saya');

  const FilterDaftar(this.label);
  final String label;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.service});

  final BlockchainService service;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _judulTab = [
    'Sertifikat kegiatan',
    'Terbitkan sertifikat',
    'Verifikasi sertifikat',
  ];

  int _tab = 0;
  List<Sertifikat> _data = const [];
  double? _saldoEth;
  bool _sedangMemuat = false;
  String? _error;
  FilterDaftar _filter = FilterDaftar.semua;
  StreamSubscription<String>? _langganan;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onWalletBerubah);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.service.initReown(context);
      if (mounted) setState(() {});
    });
    _muat();
    _langganan = widget.service
        .pantauPerubahan()
        .listen((_) => _muat(diam: true), onError: (_) {});
  }

  void _onWalletBerubah() {
    if (!mounted) return;
    _muat(diam: true);
    setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(_onWalletBerubah);
    _langganan?.cancel();
    super.dispose();
  }

  Future<void> _muat({bool diam = false}) async {
    if (_sedangMemuat) return;
    if (diam) {
      _sedangMemuat = true;
    } else {
      setState(() {
        _sedangMemuat = true;
        _error = null;
      });
    }
    try {
      final hasil = await widget.service.ambilSemua();
      final saldo = await widget.service.ambilSaldoEth();

      if (!mounted) return;
      setState(() {
        _data = hasil;
        _saldoEth = saldo;
        _error = null;
      });
    } catch (e) {
      if (!mounted || diam) return;
      setState(() => _error = BlockchainService.pesanError(e));
    } finally {
      if (mounted) setState(() => _sedangMemuat = false);
    }
  }

  List<Sertifikat> get _tampil {
    final wallet = widget.service.alamatWallet;
    return _data.where((s) {
      switch (_filter) {
        case FilterDaftar.semua:
          return true;
        case FilterDaftar.valid:
          return s.valid;
        case FilterDaftar.dicabut:
          return !s.valid;
        case FilterDaftar.milikku:
          return wallet != null && s.diterbitkanOleh(wallet);
      }
    }).toList();
  }

  Future<void> _editNama(Sertifikat s) async {
    final controller = TextEditingController(text: s.namaKegiatan);
    final namaBaru = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit nama kegiatan #${s.id}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama kegiatan baru',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final teks = controller.text.trim();
              if (teks.isNotEmpty && teks != s.namaKegiatan) {
                Navigator.pop(ctx, teks);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (namaBaru == null || !mounted) return;

    final sukses = await jalankanTransaksi(
      context,
      service: widget.service,
      judul: 'Konfirmasi edit di wallet...',
      kirim: () => widget.service.editNamaKegiatan(
        id: s.id,
        namaKegiatanBaru: namaBaru,
      ),
    );
    if (sukses) _muat(diam: true);
  }

  Future<void> _cabut(Sertifikat s) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cabut sertifikat #${s.id}?'),
        content: Text(
          '"${s.namaKegiatan}" akan ditandai DICABUT. Perubahan ini dicatat '
          'permanen di blockchain dan tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Cabut sertifikat'),
          ),
        ],
      ),
    );
    if (yakin != true || !mounted) return;

    final sukses = await jalankanTransaksi(
      context,
      service: widget.service,
      judul: 'Konfirmasi pencabutan di wallet...',
      kirim: () => widget.service.cabutSertifikat(s.id),
    );
    if (sukses) _muat(diam: true);
  }

  @override
  Widget build(BuildContext context) {
    final modal = widget.service.appKitModal;

    return Scaffold(
      appBar: AppBar(
        title: Text(_judulTab[_tab]),
        actions: [
          if (modal != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: AppKitModalConnectButton(appKit: modal),
            )
          else
            TextButton.icon(
              onPressed: () async {
                await widget.service.initReown(context);
                if (!context.mounted) return;
                if (widget.service.reownError != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Reown Error: ${widget.service.reownError}')),
                  );
                }
                setState(() {});
              },
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text('Connect'),
            ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _sedangMemuat ? null : () => _muat(),
            icon: _sedangMemuat
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _buildDaftar(),
          TerbitkanTab(
            service: widget.service,
            onBerhasil: () {
              _muat(diam: true);
              setState(() => _tab = 0);
            },
          ),
          VerifikasiTab(service: widget.service),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Daftar',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Terbitkan',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_outlined),
            selectedIcon: Icon(Icons.verified),
            label: 'Verifikasi',
          ),
        ],
      ),
    );
  }

  Widget _buildDaftar() {
    final tema = Theme.of(context);
    final tampil = _tampil;
    final wallet = widget.service.alamatWallet;

    Widget isi;
    if (_sedangMemuat && _data.isEmpty) {
      isi = const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null && _data.isEmpty) {
      isi = _KeadaanKosong(
        ikon: Icons.cloud_off_outlined,
        judul: 'Data belum bisa dimuat',
        isi: _error!,
        aksi: FilledButton.tonal(
          onPressed: () => _muat(),
          child: const Text('Coba lagi'),
        ),
      );
    } else if (tampil.isEmpty) {
      isi = _KeadaanKosong(
        ikon: Icons.inbox_outlined,
        judul: _data.isEmpty ? 'Belum ada sertifikat' : 'Tidak ada yang cocok',
        isi: _data.isEmpty
            ? 'Terbitkan sertifikat pertama lewat tab Terbitkan.'
            : _filter == FilterDaftar.milikku && wallet == null
                ? 'Hubungkan wallet terlebih dahulu untuk melihat sertifikat milik Anda.'
                : 'Ubah filter untuk melihat sertifikat lainnya.',
      );
    } else {
      isi = Column(
        children: [
          for (final s in tampil)
            SertifikatCard(
              key: ValueKey(s.id),
              sertifikat: s,
              milikSaya: wallet != null && s.diterbitkanOleh(wallet),
              onEdit: () => _editNama(s),
              onCabut: () => _cabut(s),
            ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => _muat(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '${_data.length} sertifikat tercatat di blockchain',
            style: tema.textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            wallet == null
                ? 'Wallet: Belum terhubung (klik Connect Wallet di kanan atas)'
                : 'Wallet terhubung: ${potongAlamat(wallet.hexEip55)}',
            style: tema.textTheme.bodySmall?.copyWith(
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ),
          if (wallet != null) ...[
            const SizedBox(height: 2),
            Text(
              _saldoEth == null
                  ? 'Saldo: memuat...'
                  : 'Saldo: ${_saldoEth!.toStringAsFixed(4)} SepoliaETH',
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in FilterDaftar.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null && _data.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tema.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: tema.colorScheme.onErrorContainer),
              ),
            ),
          isi,
        ],
      ),
    );
  }
}

class _KeadaanKosong extends StatelessWidget {
  const _KeadaanKosong({
    required this.ikon,
    required this.judul,
    required this.isi,
    this.aksi,
  });

  final IconData ikon;
  final String judul;
  final String isi;
  final Widget? aksi;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Icon(ikon, size: 48, color: tema.colorScheme.outline),
          const SizedBox(height: 12),
          Text(judul, style: tema.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(isi, textAlign: TextAlign.center),
          if (aksi != null) ...[const SizedBox(height: 16), aksi!],
        ],
      ),
    );
  }
}