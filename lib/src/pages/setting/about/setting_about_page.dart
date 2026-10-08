// Modified for Bilingual Lite (2026-10-07); see NOTICE. Original JHenTai portions: Apache-2.0.
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/extension/widget_extension.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SettingAboutPage extends StatefulWidget {
  const SettingAboutPage({Key? key}) : super(key: key);

  @override
  _SettingAboutPageState createState() => _SettingAboutPageState();
}

class _SettingAboutPageState extends State<SettingAboutPage> {
  String appName = '';
  String packageName = '';
  String version = '';
  String buildNumber = '';
  String author = '酱天小禽兽(JTMonster)';
  String gitRepo = 'https://github.com/cyreneEGO093/jhentai-bilingual-lite';
  String helpPage = 'https://github.com/jiangtian616/JHenTai/wiki';

  @override
  void initState() {
    PackageInfo.fromPlatform().then((packageInfo) {
      setState(() {
        appName = packageInfo.appName;
        packageName = packageInfo.packageName;
        version = packageInfo.version;
        buildNumber = packageInfo.buildNumber;
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('JHenTai · 双语轻译')),
      body: ListView(
        padding: const EdgeInsets.only(top: 16),
        children: [
          const ListTile(
              title: Text('非官方衍生版 · GPL-3.0-only'),
              subtitle: Text(
                  '个人自用实验项目。本衍生版的开发与改动完全由 GPT-6 Astra 通过 vibe coding 完成；上游和第三方代码保留原作者署名。不对可靠性、翻译准确性或后续维护作任何保证。')),
          ListTile(
              title: const Text('开源许可'),
              onTap: () => showLicensePage(
                  context: context, applicationName: 'JHenTai Bilingual Lite')),
          ListTile(
              title: Text('version'.tr),
              subtitle: Text(version.isEmpty
                  ? '1.0.0'
                  : version + (buildNumber.isEmpty ? '' : '+$buildNumber'))),
          ListTile(
              title: const Text('JHenTai 上游作者'),
              subtitle: SelectableText(author)),
          ListTile(
            title: const Text('本衍生版源码'),
            subtitle: SelectableText(gitRepo),
            onTap: () =>
                launchUrlString(gitRepo, mode: LaunchMode.externalApplication),
          ),
          ListTile(
            title: const Text('手动下载本衍生版'),
            subtitle: const Text('不会自动检查、下载或安装更新。'),
            onTap: () => launchUrlString('$gitRepo/releases',
                mode: LaunchMode.externalApplication),
          ),
          ListTile(
            title: const Text('上游使用文档（不包含双语轻译）'),
            subtitle: SelectableText(helpPage),
            onTap: () =>
                launchUrlString(helpPage, mode: LaunchMode.externalApplication),
          ),
        ],
      ).withListTileTheme(context),
    );
  }
}
