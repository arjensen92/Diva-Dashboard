import 'package:flutter/material.dart';

import 'win95.dart';

/// Shows a Win95-styled modal explaining that an OAuth-protected
/// service can't connect because the necessary credentials aren't
/// present in `<projectRoot>/.env`. Surfaced when the user clicks
/// "Connect Google Calendar" / "Connect Spotify" on a fresh public
/// install — otherwise the connect attempt fails silently and the
/// button just looks broken.
Future<void> showOAuthSetupRequiredDialog(
  BuildContext context, {
  required String serviceName,
  required List<String> envVarNames,
  required String credentialUrl,
  String credentialUrlLabel = 'where to get credentials',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      insetPadding: const EdgeInsets.all(40),
      child: SizedBox(
        width: 460,
        child: Win95Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Win95TitleBar(
                title: '$serviceName setup required',
                titleFontSize: 12,
                buttonSize: 22,
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                leading: const Icon(Icons.warning_amber_rounded,
                    size: 16, color: Colors.white),
                onClose: () => Navigator.of(ctx).pop(),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$serviceName isn\'t configured yet.',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'To connect, create or edit the file '
                      '"<projectRoot>/.env" (a plain text file next to '
                      'the dashboard\'s data JSONs) and add these entries:',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Win95.sunkenBorder(),
                      ),
                      child: SelectableText(
                        envVarNames.map((n) => '$n=your_value_here').join('\n'),
                        style: const TextStyle(
                          fontFamily: 'Courier New',
                          fontSize: 12,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'See $credentialUrlLabel:',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      credentialUrl,
                      style: const TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 11,
                        color: Color(0xFF0000A0),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'After saving the .env file, restart the dashboard '
                      'and click Connect again.',
                      style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Win95Button(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          child: Text(
                            'OK',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
