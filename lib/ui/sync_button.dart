import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../sync/drive_sync.dart';

/// "Tümünü senkronize et" — durum simgesi + tıklayınca tam senkron
class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();
    final (icon, tip) = switch (sync.state) {
      SyncState.signedOut => (Icons.cloud_off_outlined, 'Google ile giriş yap'),
      SyncState.idle => (Icons.cloud_done_outlined,
          'Tümünü senkronize et${sync.lastSync != null ? '\nSon: ${TimeOfDay.fromDateTime(sync.lastSync!).format(context)}' : ''}'),
      SyncState.syncing => (Icons.sync, 'Senkronize ediliyor…'),
      SyncState.error => (Icons.sync_problem, 'Hata: ${sync.lastError ?? ''}'),
    };
    return IconButton(
      tooltip: tip,
      icon: sync.state == SyncState.syncing
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, color: sync.state == SyncState.error ? Theme.of(context).colorScheme.error : null),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        if (!sync.signedIn) {
          if (!sync.configured) {
            showNotConfigured(context);
            return;
          }
          await sync.signIn();
          return;
        }
        final r = await sync.syncAll();
        if (r != null) messenger.showSnackBar(SnackBar(content: Text('Senkron tamam: $r')));
        if (sync.state == SyncState.error) messenger.showSnackBar(SnackBar(content: Text('Senkron hatası: ${sync.lastError}')));
      },
    );
  }
}

class AccountButton extends StatelessWidget {
  const AccountButton({super.key});
  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();
    return PopupMenuButton<String>(
      tooltip: 'Hesap',
      icon: CircleAvatar(
        radius: 14,
        child: Text(sync.email?.substring(0, 1).toUpperCase() ?? '?', style: const TextStyle(fontSize: 13)),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(sync.email ?? 'Giriş yapılmadı')),
        if (!sync.signedIn) const PopupMenuItem(value: 'in', child: Text('Google ile giriş yap')),
        if (sync.signedIn) const PopupMenuItem(value: 'sync', child: Text('Tümünü senkronize et')),
        if (sync.signedIn) const PopupMenuItem(value: 'out', child: Text('Çıkış yap')),
      ],
      onSelected: (v) {
        switch (v) {
          case 'in':
            sync.configured ? sync.signIn() : showNotConfigured(context);
          case 'sync':
            sync.syncAll();
          case 'out':
            sync.signOut();
        }
      },
    );
  }
}

void showNotConfigured(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Senkron henüz ayarlanmadı'),
      content: const Text('Bu sürümde Google hesabı bağlantısı tanımlı değil. Notların bu cihazda güvenle kaydediliyor; '
          'Google Cloud kurulumu yapılıp yeni sürüm kurulunca senkron açılacak.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
    ),
  );
}
