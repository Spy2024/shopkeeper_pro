import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

/// Shows an explicit ownership confirmation before importing an old,
/// unscoped local database into the currently authenticated account.
Future<bool> confirmLegacyDatabaseImport(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Import existing shop data?'),
      content: const Text(
        'An older local database was found on this device. Import it only if '
        'you recognise this shop data and it belongs to the account you just '
        'signed into. The original file will be kept as a recovery copy. '
        'If you are unsure, cancel and ask the shop owner before continuing.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Yes, import my shop data'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return false;
  try {
    await context.read<AuthProvider>().migrateLegacyDatabaseForCurrentUser();
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not import the old database: '
            '${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
    return false;
  }
}
