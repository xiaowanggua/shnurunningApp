import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // 暂不集成，后续添加

// API 配置
const String BASE_URL = 'https://cpapp.1lesson.cn/api/route';
const String URL_START_RUNNING = '$BASE_URL/insertStartRunning';
const String URL_SIGN_IN = '$BASE_URL/selectStudentSignIn';
const String URL_FINISH_RUNNING = '$BASE_URL/insertFinishRunning';

class ProgressPage extends StatefulWidget {
  final String? userId;
  final int minutes;
  final int seconds;
  final double distanceKm;
  final int count;
  final bool isQuickMode;
  final bool isResuming;

  const ProgressPage({
    super.key,
    required this.userId,
    required this.minutes,
    required this.seconds,
    required this.distanceKm,
    required this.count,
    required this.isQuickMode,
    required this.isResuming,
  });

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  Timer? _timer;
  int _remainingSeconds = 0;
  int _currentCount = 0;
  String? _recordId;
  DateTime? _startTime;
  bool _isCancelled = false;
  // FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin(); // 暂不集成

  @override
  void initState() {
    super.initState();
    // _initializeNotifications(); // 暂不集成
    _currentCount = widget.count;
    _remainingSeconds = widget.minutes * 60 + widget.seconds;

    if (widget.isResuming) {
      _loadRunState();
    } else {
      if (widget.userId == null || widget.userId!.isEmpty) {
        _showErrorAndPop('用户ID无效，无法开始跑步。');
        return;
      }
      _startNewRunSequence();
    }
  }

  // void _initializeNotifications() async { // 暂不集成
  //   const AndroidInitializationSettings initializationSettingsAndroid =
  //       AndroidInitializationSettings('@mipmap/ic_launcher'); // Ensure you have this icon
  //   const InitializationSettings initializationSettings = InitializationSettings(
  //     android: initializationSettingsAndroid,
  //   );
  //   await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  // }

  // Future<void> _showNotification(String title, String body) async { // 暂不集成
  //   const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
  //     'shnurunning_channel_id', // id
  //     'ShnuRunning Notifications', // title
  //     channelDescription: 'Notifications for ShnuRunning app', // description
  //     importance: Importance.max,
  //     priority: Priority.high,
  //     showWhen: false,
  //   );
  //   const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
  //   await flutterLocalNotificationsPlugin.show(
  //     0, // notification id
  //     title,
  //     body,
  //     platformChannelSpecifics,
  //     payload: 'item x',
  //   );
  // }

  Future<void> _loadRunState() async {
    print("尝试恢复跑步状态...");
    final prefs = await SharedPreferences.getInstance();
    _recordId = prefs.getString('run_details_recordId');
    _currentCount = prefs.getInt('run_details_currentCount') ?? widget.count;
    _remainingSeconds = prefs.getInt('run_details_remainingSeconds') ?? (widget.minutes * 60 + widget.seconds);
    String? startTimeString = prefs.getString('run_details_startTime');

    if (_recordId != null && startTimeString != null) {
      _startTime = DateTime.parse(startTimeString);
      // 如果是快速模式，直接认为完成，或者根据实际业务调整
      if (widget.isQuickMode && _currentCount > 0) {
        print("快速模式恢复，直接进行下一次或结束");
        // 模拟一次完成
        _runCompleted();
        return;
      }
      _startTimer();
      print("跑步状态已恢复: recordId: $_recordId, currentCount: $_currentCount, remainingSeconds: $_remainingSeconds");
    } else {
      print("未找到有效的跑步状态，或状态已损坏，将返回主页。");
      _showErrorAndPop('无法恢复跑步状态，请重新开始。');
    }
  }

  Future<void> _saveRunState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_recordId != null && _startTime != null && _currentCount > 0 && !_isCancelled) {
      await prefs.setString('run_details_recordId', _recordId!);
      await prefs.setInt('run_details_currentCount', _currentCount);
      await prefs.setInt('run_details_remainingSeconds', _remainingSeconds);
      await prefs.setString('run_details_startTime', _startTime!.toIso8601String());
      await prefs.setBool('is_run_in_progress', true); // 标记主页面按钮状态
      print("跑步状态已保存: recordId: $_recordId, count: $_currentCount, remaining: $_remainingSeconds");
    } else {
      await _clearRunState(); // 如果不满足保存条件（如已取消或完成），则清除
    }
  }

  Future<void> _clearRunState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('run_details_recordId');
    await prefs.remove('run_details_currentCount');
    await prefs.remove('run_details_remainingSeconds');
    await prefs.remove('run_details_startTime');
    await prefs.setBool('is_run_in_progress', false); // 标记主页面按钮状态
    print("跑步状态已清除");
  }

  void _showErrorAndPop(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
      Navigator.pop(context, {'runCompleted': false, 'runCancelled': true}); // Indicate cancellation or failure
    }
  }

  Future<void> _startNewRunSequence() async {
    print("开始新的跑步序列，用户ID: ${widget.userId}");
    if (_isCancelled) return;

    // 1. 新建一次跑步
    try {
      print("尝试新建跑步...");
      final response = await http.post(
        Uri.parse(URL_START_RUNNING),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'userId': widget.userId!},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print("新建跑步API响应: $responseData");
        if (responseData['status'] == 'fail' && responseData['data']?['errCode'] == 10002) {
          print("新建跑步失败: ${responseData['data']?['errMsg']}");
          _showErrorAndPop('请在体锻打卡点开一次开始跑步，并直接结束一次。');
          return;
        } else if (responseData['status'] != 'fail' && responseData['data']?['runningRecord'] != null) {
          _recordId = responseData['data']['runningRecord'].toString();
          _startTime = DateTime.now();
          print("新建跑步成功，Record ID: $_recordId, 开始时间: $_startTime");
          await _saveRunState(); // 保存初始状态
          // 2. 打卡点0,1,2,3
          if (widget.isQuickMode) {
            print("快速模式，跳过打卡点和倒计时，直接完成本次跑步。");
            await _performFinishRun(); // 快速模式直接结束
            _runCompleted();
          } else {
            await _performSignIns();
            _startTimer();
          }
        } else {
          print("新建跑步失败，未知错误或响应格式不符: $responseData");
          _showErrorAndPop('新建跑步失败，请检查网络或稍后再试。');
        }
      } else {
        print("新建跑步API请求失败，状态码: ${response.statusCode}, 响应: ${response.body}");
        _showErrorAndPop('新建跑步请求失败 (HTTP ${response.statusCode})，请检查网络。');
      }
    } catch (e) {
      print("新建跑步时发生异常: $e");
      _showErrorAndPop('新建跑步时发生错误: ${e.toString()}');
    }
  }

  Future<void> _performSignIns() async {
    if (_isCancelled || _recordId == null) return;
    print("开始执行打卡点操作，Record ID: $_recordId");
    for (int i = 0; i < 4; i++) {
      if (_isCancelled) break;
      try {
        print("尝试打卡点: $i");
        Map<String, dynamic> pointsData = {
          "userId": widget.userId!,
          "recordId": _recordId!,
          "posLongitude": 0.0,
          "posLatitude": 0.0,
        };
        // 实际坐标，根据需要调整或从配置读取
        if (i == 0) {
          pointsData["posLongitude"] = 121.51818147705078;
          pointsData["posLatitude"] = 30.837721567871094;
        } else if (i == 1) {
          pointsData["posLongitude"] = 121.52092847705076;
          pointsData["posLatitude"] = 30.834883567871294;
        } else if (i == 2) {
          pointsData["posLongitude"] = 121.51926147705322;
          pointsData["posLatitude"] = 30.835872567871354;
        } else if (i == 3) {
          pointsData["posLongitude"] = 121.51749847705033;
          pointsData["posLatitude"] = 30.835306567871091;
        }

        final response = await http.post(
          Uri.parse(URL_SIGN_IN),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: pointsData.map((key, value) => MapEntry(key, value.toString())), // Ensure all values are strings for x-www-form-urlencoded
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          print("打卡点 $i 成功: ${response.body}");
        } else {
          print("打卡点 $i 失败，状态码: ${response.statusCode}, 响应: ${response.body}");
          // 可以选择是否因为单个打卡点失败而中止整个流程
        }
        await Future.delayed(const Duration(milliseconds: 500)); // 短暂延迟，模拟真实操作
      } catch (e) {
        print("打卡点 $i 时发生异常: $e");
        // 处理异常
      }
    }
    print("所有打卡点操作完成。");
  }

  void _startTimer() {
    if (_isCancelled) return;
    _startTime ??= DateTime.now(); // 如果是恢复，_startTime应该已加载，否则设为当前
    // 如果是恢复，需要根据已过时间调整_remainingSeconds
    if (widget.isResuming && _startTime != null) {
        final elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;
        int newRemaining = (widget.minutes * 60 + widget.seconds) - elapsedSeconds;
        _remainingSeconds = newRemaining > 0 ? newRemaining : 0;
        print("恢复计时器，已过 $elapsedSeconds 秒，剩余 $_remainingSeconds 秒");
    }

    _timer?.cancel(); // Cancel any existing timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isCancelled) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          _saveRunState(); // 每秒保存一次状态，确保进度
        } else {
          timer.cancel();
          print("倒计时结束，执行结束打卡操作。");
          _performFinishRun();
          _runCompleted();
        }
      });
    });
    print("计时器已启动，总时长: $_remainingSeconds 秒");
  }

  Future<void> _performFinishRun({bool isCancel = false}) async {
    if (_recordId == null || widget.userId == null) {
      print("无法结束跑步：recordId 或 userId 为空。");
      return;
    }
    print("执行结束打卡操作，Record ID: $_recordId, 是否取消: $isCancel");

    int totalTimeSeconds;
    if (isCancel) {
      totalTimeSeconds = 10; // 取消时，totalTime为10
    } else if (_startTime != null) {
      totalTimeSeconds = DateTime.now().difference(_startTime!).inSeconds;
      // 确保 totalTime 不小于设定的跑步时间，除非是提前完成或快速模式
      int configuredTotalSeconds = widget.minutes * 60 + widget.seconds;
      if (!widget.isQuickMode && totalTimeSeconds < configuredTotalSeconds) {
        // totalTimeSeconds = configuredTotalSeconds; // 或者使用实际经过时间，取决于业务逻辑
      }
    } else {
      totalTimeSeconds = widget.minutes * 60 + widget.seconds; // 备用，理论上_startTime不应为空
    }
    if (widget.isQuickMode && !isCancel) {
        totalTimeSeconds = widget.minutes * 60 + widget.seconds; // 快速模式按设定时间
    }

    final String jsonData = json.encode({
      "userId": widget.userId!,
      "runningRecordId": _recordId!,
      "mileage": widget.distanceKm,
      "speedAllocation": 0,
      "totalTime": isCancel ? 10 : (totalTimeSeconds / 60.0).toStringAsFixed(1), // API要求的是分钟，保留一位小数
      "data": []
    });

    try {
      print("发送结束跑步请求: $jsonData");
      final response = await http.post(
        Uri.parse(URL_FINISH_RUNNING),
        headers: {'Content-Type': 'application/json'},
        body: jsonData,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print("结束跑步成功: ${response.body}");
      } else {
        print("结束跑步失败，状态码: ${response.statusCode}, 响应: ${response.body}");
        // 即使API失败，也可能需要清理本地状态
      }
    } catch (e) {
      print("结束跑步时发生异常: $e");
    }
    await _clearRunState(); // 无论成功与否，都清除本地的跑步状态
  }

  void _runCompleted() {
    if (_isCancelled) return;
    print("单次跑步完成，当前次数: $_currentCount");
    setState(() {
      _currentCount--;
    });
    _recordId = null; // 重置 recordId 以便下次新建
    _startTime = null;
    _remainingSeconds = widget.minutes * 60 + widget.seconds; // 重置计时器

    if (_currentCount > 0) {
      print("还有剩余次数: $_currentCount，准备开始下一次跑步。");
      _saveRunState(); // 保存次数减少后的状态
      _startNewRunSequence(); // 开始下一次
    } else {
      print("所有跑步次数已完成。");
      // await _showNotification('跑步完成', '体锻打卡 ${widget.count} 次结束'); // 暂不集成
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('体锻打卡 ${widget.count} 次结束')),
      );
      _clearRunState();
      Navigator.pop(context, {'runCompleted': true, 'runCancelled': false});
    }
  }

  Future<void> _cancelRun() async {
    print("用户点击取消按钮。");
    setState(() {
      _isCancelled = true;
    });
    _timer?.cancel();
    await _performFinishRun(isCancel: true);
    await _clearRunState();
    Navigator.pop(context, {'runCompleted': false, 'runCancelled': true});
  }

  @override
  void dispose() {
    _timer?.cancel();
    // 如果页面意外关闭（非正常取消或完成），且仍在跑步中，则保存状态
    // 正常完成或取消时，_clearRunState 已经被调用
    // if (!_isCancelled && _currentCount > 0 && _recordId != null) {
    //   _saveRunState(); // 确保在意外退出时保存状态
    // }
    print("ProgressPage disposed.");
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isCancelled || _currentCount == 0, // 只有在取消或全部完成后才允许通过系统返回键退出
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (!_isCancelled && _currentCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请使用取消按钮退出跑步。')),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('跑步进度'),
          automaticallyImplyLeading: false, // 禁用默认返回按钮，强制使用取消按钮
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '剩余时间: ${_formatDuration(_remainingSeconds)}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                Text(
                  '剩余次数: $_currentCount / ${widget.count}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 40),
                if (_recordId != null) // 仅在成功获取recordId后显示
                  Text(
                    '当前任务ID: $_recordId',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _cancelRun,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                    textStyle: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  child: const Text('取消', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
