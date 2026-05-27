part of 'main_settings.dart';

class ClearVpnCacheSettingsTile extends StatefulWidget {
  const ClearVpnCacheSettingsTile({
    super.key,
    required this.controller,
    required this.strings,
  });

  final VpnController controller;
  final AppStrings strings;

  @override
  State<ClearVpnCacheSettingsTile> createState() =>
      _ClearVpnCacheSettingsTileState();
}

class _ClearVpnCacheSettingsTileState extends State<ClearVpnCacheSettingsTile> {
  bool _isClearing = false;

  @override
  Widget build(BuildContext context) {
    return _SettingsNavigationTile(
      icon: Icons.delete_forever_rounded,
      title: widget.strings.clearVpnCacheLabel,
      subtitle: widget.controller.canClearVpnCache
          ? widget.strings.clearVpnCacheSubtitle
          : widget.strings.clearVpnCacheDisabledSubtitle,
      enabled: widget.controller.canClearVpnCache && !_isClearing,
      onTap: _confirmAndClear,
    );
  }

  Future<void> _confirmAndClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(widget.strings.clearVpnCacheDialogTitle),
          content: Text(widget.strings.clearVpnCacheDialogMessage),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_forever_rounded),
              label: Text(widget.strings.clearVpnCacheConfirmAction),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isClearing = true;
    });

    try {
      final result = await widget.controller.clearVpnCache();
      if (!mounted) {
        return;
      }
      final message = result.hasFailures
          ? widget.strings.clearVpnCachePartialMessage(
              result.deletedCount,
              result.failedPaths.length,
            )
          : widget.strings.clearVpnCacheSuccessMessage(result.deletedCount);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.strings.clearVpnCacheFailedMessage(error)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }
}
