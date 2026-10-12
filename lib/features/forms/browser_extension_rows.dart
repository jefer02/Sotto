import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/theme.dart';
import '../../core/platform/external_links.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/display.dart';
import '../../l10n/l10n.dart';
import '../../services/screen/browser_bridge.dart';

/// Where to get the Sotto Bridge extension — opened in the presenter's
/// browser, never fetched by Sotto. The Edge listing's ID is only known once
/// it is published, so until then it is a store search.
const bridgeStoreUrls = {
  BrowserKind.chrome: 'https://chromewebstore.google.com/detail/oaompapbahpnpllcdpidhojbdoblcpil',
  BrowserKind.edge: 'https://microsoftedge.microsoft.com/addons/search/sotto%20bridge',
  BrowserKind.firefox: 'https://addons.mozilla.org/firefox/addon/sotto-bridge/',
};

/// One row per browser: whether its Sotto Bridge extension is connected,
/// and an "Install extension" button (the store page) when it isn't.
/// Settings → Forms and the welcome dialog both show these.
class BrowserExtensionRows extends ConsumerWidget {
  const BrowserExtensionRows({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final connected = ref.watch(bridgeStatusProvider).value ?? ref.read(browserBridgeProvider).connected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in BrowserKind.values) ...[
          if (b.index > 0) Divider(height: 1, thickness: 1, color: p.hairline),
          SettingRow(
            title: b.label,
            subtitle: connected.contains(b) ? l.bridgeConnected : l.bridgeNotInstalled,
            leading: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected.contains(b) ? p.confirmed : p.inkDisabled,
              ),
            ),
            trailing: connected.contains(b)
                ? null
                : SottoButton(
                    label: l.bridgeInstall,
                    size: ButtonSize.small,
                    onPressed: () => unawaited(openExternal(bridgeStoreUrls[b]!)),
                  ),
          ),
        ],
      ],
    );
  }
}
