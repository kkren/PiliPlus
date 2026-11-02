import 'package:PiliPlus/pages/setting/widgets/bili_roaming_dialog.dart';
import 'package:PiliPlus/services/bili_roaming/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('enabling roaming requires a server; saving retains options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    BiliRoamingConfig? saved;
    String? accountKey = 'account-key';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<BiliRoamingConfig>(
                  context: context,
                  builder: (_) => BiliRoamingDialog(
                    config: BiliRoamingConfig(
                      accessKeyProvider: () => accountKey,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('启用哔哩漫游'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('启用前请填写服务端地址'), findsOneWidget);
    expect(saved, isNull);
    await tester.enterText(
      find.byType(TextFormField).first,
      'https://roaming.example/proxy',
    );
    await tester.tap(find.text('始终使用漫游'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.textContaining('默认向配置的服务端发送'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved!.enabled, isTrue);
    expect(saved!.server, 'https://roaming.example/proxy');
    expect(saved!.force, isTrue);
    expect(saved!.accessKey, 'account-key');
    accountKey = null;
    expect(saved!.accessKey, isEmpty);
    expect(saved!.area, 'hk');
  });
}
