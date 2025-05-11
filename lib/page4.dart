import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// 模拟日志数据
// 注意：为了在 HelpPage 的多个实例或热重载后保持日志的某种程度的“一致性”或避免重复初始化，
// 可以考虑将 _logMessages 移到更全局的状态管理中（如 AppState），或者接受它在 HelpPage 重建时可能重置（除非应用重启）。
// 对于当前需求，保持其为顶级变量，每次 addLog 会追加到这个静态列表。
List<String> _logMessages = [
  "App initialized at ${DateTime.now()}",
  "User navigated to MainPage",
  // ... more logs will be added dynamically by the app
];

// 函数用于在应用其他地方添加日志
void addLog(String message) {
  String logEntry = "${DateTime.now()}: $message";
  print("LOG: $logEntry"); // 打印到控制台
  _logMessages.add(logEntry);
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Future<void> _saveLogsToFile(BuildContext context) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      // 使用更安全的文件名字符替换
      final String timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final filePath = '${directory.path}/shnurunning_logs_$timestamp.txt';
      final file = File(filePath);

      // 将日志列表转换为字符串，每条日志占一行
      final String logContent = _logMessages.join('\n');
      await file.writeAsString(logContent);

      addLog("Logs saved to $filePath");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('日志已保存到: $filePath')),
        );
      }
    } catch (e) {
      addLog("Error saving logs: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存日志失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    addLog("User navigated to HelpPage");
    return Scaffold(
      appBar: AppBar(
        title: const Text('帮助与用法'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: <Widget>[
            Text(
              '应用用法介绍',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              '欢迎使用 SHNU 跑步助手！\n\n'
              '1. 账户管理:\n'
              '   - 在主页左上角的下拉框中，您可以选择 \'新建\' 来创建一个新的跑步账户。\n'
              '   - 在新建账户页面，输入备注名称和您的账号ID。点击 \'获取\' 按钮可以尝试自动填充（此功能待具体实现）。\n'
              '   - 保存后，新账户会出现在下拉列表中。\n'
              '   - 选择一个已有的账户后，其账号ID会自动复制到剪贴板，方便您在其他地方使用。\n\n'
              '2. 参数设置:\n'
              '   - 在主页中央区域，设置您每次跑步的 \'分钟\', \'秒\', \'公里数\' 和 \'次数\'。\n'
              '   - \'快速完成模式\' 勾选后，将跳过实际的打卡点和倒计时，直接标记为完成（用于测试或特殊情况）。\n'
              '   - 所有这些设置在您修改后都会自动保存，下次打开应用时会恢复。\n\n'
              '3. 开始跑步:\n'
              '   - 设置好参数并选择账户后，点击 \'开始\' 按钮。\n'
              '   - 应用会进入跑步进度页面，显示倒计时和剩余次数。\n'
              '   - 如果中途需要停止，可以点击 \'取消\' 按钮。\n'
              '   - 如果应用在跑步过程中意外关闭，下次打开时会检测到未完成的打卡并尝试自动取消，同时会弹出提示。\n'
              '   - 跑步完成后，会有系统通知提示。\n\n'
              '4. 查看进度:\n'
              '   - 如果一次跑步任务已开始但未完成（例如您退出了进度页面但未取消），主页的按钮会变为 \'查看进度\'。点击它可以返回到当前的跑步进度页面。\n\n'
              '5. 日志:\n'
              '   - 本应用会记录一些关键操作的日志，您可以在此帮助页面点击下方的按钮将当前日志保存到本地文件中，方便排查问题。\n'
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => _saveLogsToFile(context),
              child: const Text('保存日志到本地'),
            ),
            const SizedBox(height: 20),
            Text(
              '日志预览:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Scrollbar(
                thumbVisibility: true, // 确保滚动条可见性
                child: ListView.builder(
                  primary: true, // 将此处的 primary 设置为 true
                  itemCount: _logMessages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Text(_logMessages[index], style: const TextStyle(fontSize: 12)),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
