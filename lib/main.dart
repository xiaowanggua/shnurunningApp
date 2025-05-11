import 'dart:async'; // For StreamSubscription
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // 用于 json 编解码
import 'package:flutter/services.dart'; // 用于剪贴板 和 PlatformException
import 'package:connectivity_plus/connectivity_plus.dart'; // 网络检查
import 'package:http/http.dart' as http; // For API calls in _checkUnfinishedRun

// 导入新页面
import 'page2.dart'; // NewAccountPage
import 'page3.dart'; // ProgressPage and API constants like URL_FINISH_RUNNING
import 'page4.dart'; // HelpPage & addLog

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  addLog("Application starting. SharedPreferences initialized.");

  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(prefs),
      child: const ShnuRunning(),
    ),
  );
}

class ShnuRunning extends StatelessWidget {
  const ShnuRunning({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'shnurunning',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyanAccent),
      ),
      home: const MainPage(),
    );
  }
}

class AppState extends ChangeNotifier {
  List<Map<String, String>> _accountsList = [];
  String? _currentUserId;
  final SharedPreferences? _prefs;

  AppState(this._prefs) {
    _loadAccounts();
  }

  List<Map<String, String>> get accountsList => _accountsList;
  String? get currentUserId => _currentUserId;

  Future<void> _loadAccounts() async {
    if (_prefs == null) {
      addLog("AppState: SharedPreferences not available for loading accounts.");
      return;
    }
    final String? accountsJson = _prefs?.getString('accounts_list');
    if (accountsJson != null) {
      try {
        final List<dynamic> decodedList = json.decode(accountsJson);
        _accountsList = decodedList.map((item) => Map<String, String>.from(item)).toList();
        addLog("AppState: Accounts loaded: ${_accountsList.length} accounts.");
      } catch (e) {
        addLog("AppState: Error decoding accounts_list: $e");
        _accountsList = [];
      }
    } else {
      addLog("AppState: No accounts_list found in SharedPreferences.");
    }
    notifyListeners();
  }

  Future<void> addAccount(Map<String, String> account) async {
    if (_prefs == null) {
      addLog("AppState: SharedPreferences not available for adding account.");
      return;
    }
    if (account['name'] == '新建') {
      addLog("AppState: Attempted to add account with reserved name '新建'. Skipped.");
      return;
    }
    if (_accountsList.any((acc) => acc['name'] == account['name'] || acc['userid'] == account['userid'])) {
      addLog("AppState: Account with name '${account['name']}' or ID '${account['userid']}' already exists. Skipped.");
      return;
    }

    _accountsList.add(account);
    await _prefs?.setString('accounts_list', json.encode(_accountsList));
    addLog("AppState: Account added: ${account['name']}. Total accounts: ${_accountsList.length}.");
    notifyListeners();
  }

  Future<void> removeAccount(String accountName) async {
    if (_prefs == null) {
      addLog("AppState: SharedPreferences not available for removing account.");
      return;
    }
    if (accountName == '新建') {
      addLog("AppState: Attempt to delete '新建' account skipped.");
      return;
    }
    final originalLength = _accountsList.length;
    _accountsList.removeWhere((account) => account['name'] == accountName);

    if (_accountsList.length < originalLength) {
      await _prefs?.setString('accounts_list', json.encode(_accountsList));
      addLog("AppState: Account '$accountName' removed. Total accounts: ${_accountsList.length}.");
      if (currentUserId != null) {
        bool currentAccountWasRemoved = !_accountsList.any((acc) => acc['userid'] == _currentUserId);
        if (currentAccountWasRemoved) {
          _currentUserId = null;
          addLog("AppState: Current selected account was removed, resetting currentUserId.");
        }
      }
    } else {
      addLog("AppState: Account '$accountName' not found for removal.");
    }
    notifyListeners();
  }

  void setCurrentUserId(String? userId) {
    if (_currentUserId != userId) {
      _currentUserId = userId;
      addLog("AppState: Current User ID set to: $userId");
      notifyListeners();
    }
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  String _selectedAccountName = '新建';
  final TextEditingController _kmController = TextEditingController();
  int? _selectedMinutes;
  int? _selectedSeconds;
  int? _selectedCount;
  bool _isQuickCompleteMode = false;
  String _startButtonText = '开始';
  bool _isRunInProgress = false; // Always false, "View Progress" is removed
  ConnectivityResult _connectivityResult = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // Method to show a Snackbar when there's no internet
  void _showNoInternetSnackbar() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无网络连接，请检查您的网络设置。'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    addLog("MainPage: initState called.");
    _initConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    _loadPersistedData();
  }

  Future<void> _initConnectivity() async {
    addLog("MainPage: Initializing connectivity check.");
    late ConnectivityResult connectivityResult;
    try {
      connectivityResult = await _connectivity.checkConnectivity();
      addLog("MainPage: Connectivity check result: $connectivityResult");
    } on PlatformException catch (e) {
      addLog("MainPage: Failed to check connectivity: ${e.toString()}");
      connectivityResult = ConnectivityResult.none;
    }
    if (!mounted) {
      addLog("MainPage: Connectivity check completed but widget not mounted. Discarding result.");
      return;
    }
    _updateConnectionStatus(connectivityResult);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    addLog("MainPage: Connectivity status updated to: $result");
    if (mounted) {
      setState(() {
        _connectivityResult = result;
      });
    }
    if (result == ConnectivityResult.none) {
      _showNoInternetSnackbar();
      addLog("MainPage: No internet connection detected. Snackbar shown.");
    }
  }

  Future<void> _loadPersistedData() async {
    addLog("MainPage: Loading persisted data and resetting run state.");
    final prefs = await SharedPreferences.getInstance();

    // Always clear previous run state on load to remove "View Progress" functionality
    await _clearLocalRunState(prefs); // This also sets 'is_run_in_progress' to false in prefs

    final selectedMinutes = prefs.getInt('selected_minutes');
    final selectedSeconds = prefs.getInt('selected_seconds');
    final kmValue = prefs.getString('km_value') ?? '';
    final selectedCount = prefs.getInt('selected_count');
    final isQuickCompleteMode = prefs.getBool('quick_complete_mode') ?? false;

    final String? lastSelectedAccountNameFromPrefs = prefs.getString('last_selected_account_name');

    addLog("MainPage: Loaded from prefs - minutes: $selectedMinutes, seconds: $selectedSeconds, km: '$kmValue', count: $selectedCount, quickMode: $isQuickCompleteMode, runInProgress: false (forced), lastAccount: '$lastSelectedAccountNameFromPrefs'");

    if (mounted) {
      setState(() {
        _selectedMinutes = selectedMinutes;
        _selectedSeconds = selectedSeconds;
        _kmController.text = kmValue;
        _selectedCount = selectedCount;
        _isQuickCompleteMode = isQuickCompleteMode;
        _isRunInProgress = false; // Explicitly set to false
        _startButtonText = '开始'; // Explicitly set to '开始'
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        addLog("MainPage: PostFrameCallback for account resolution - widget not mounted.");
        return;
      }

      final appState = Provider.of<AppState>(context, listen: false);
      String resolvedSelectedAccountName = '新建';
      String? resolvedUserId;

      if (lastSelectedAccountNameFromPrefs != null && lastSelectedAccountNameFromPrefs != '新建') {
        final existingAccount = appState.accountsList.firstWhere(
          (acc) => acc['name'] == lastSelectedAccountNameFromPrefs,
          orElse: () => <String, String>{},
        );

        if (existingAccount.isNotEmpty) {
          resolvedSelectedAccountName = lastSelectedAccountNameFromPrefs;
          resolvedUserId = existingAccount['userid'];
        } else {
          resolvedSelectedAccountName = '新建';
          resolvedUserId = null;
        }
      } else {
        resolvedSelectedAccountName = '新建';
        resolvedUserId = null;
      }

      if (resolvedSelectedAccountName == '新建') {
        if (appState.currentUserId != null) {
          appState.setCurrentUserId(null);
        }
      } else {
        if (appState.currentUserId != resolvedUserId) {
          appState.setCurrentUserId(resolvedUserId);
        }
      }

      if (mounted && _selectedAccountName != resolvedSelectedAccountName) {
        setState(() {
          _selectedAccountName = resolvedSelectedAccountName;
        });
      }
    });
  }

  Future<void> _savePersistedData() async {
    addLog("MainPage: Saving persisted data.");
    final prefs = await SharedPreferences.getInstance();
    if (_selectedMinutes != null) await prefs.setInt('selected_minutes', _selectedMinutes!);
    if (_selectedSeconds != null) await prefs.setInt('selected_seconds', _selectedSeconds!);
    await prefs.setString('km_value', _kmController.text);
    if (_selectedCount != null) await prefs.setInt('selected_count', _selectedCount!);
    await prefs.setBool('quick_complete_mode', _isQuickCompleteMode);
    await prefs.setString('last_selected_account_name', _selectedAccountName);
    addLog("MainPage: Persisted data saved. Last selected account: $_selectedAccountName");
  }

  Future<void> _clearLocalRunState(SharedPreferences prefs) async {
    addLog("MainPage: Clearing local run state from SharedPreferences.");
    await prefs.remove('run_details_recordId');
    await prefs.remove('run_details_currentCount');
    await prefs.remove('run_details_remainingSeconds');
    await prefs.remove('run_details_startTime');
    await prefs.remove('run_details_userId');
    await prefs.remove('run_details_distanceKm');
    await prefs.setBool('is_run_in_progress', false);
    addLog("MainPage: Local run state cleared.");
  }

  @override
  void dispose() {
    addLog("MainPage: dispose called. Saving data.");
    _connectivitySubscription?.cancel();
    _savePersistedData();
    _kmController.dispose();
    super.dispose();
  }

  void _navigateToWindow2() async {
    addLog("MainPage: Navigating to NewAccountPage (Window2).");
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewAccountPage()),
    );
    addLog("MainPage: Returned from NewAccountPage with result: $result");
    if (result == true && mounted) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.accountsList.isNotEmpty) {
        final newAccount = appState.accountsList.last;
        setState(() {
          _selectedAccountName = newAccount['name']!;
        });
        appState.setCurrentUserId(newAccount['userid']);
        addLog("MainPage: New account '${newAccount['name']}' selected after returning from NewAccountPage.");
      } else {
        addLog("MainPage: Returned from NewAccountPage, but no accounts in list to select.");
        setState(() {
          _selectedAccountName = '新建';
        });
        appState.setCurrentUserId(null);
      }
    }
  }

  void _navigateToHelpPage() {
    addLog("MainPage: Navigating to HelpPage.");
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HelpPage()),
    );
  }

  void _navigateToProgressPage() async {
    addLog("MainPage: '$_startButtonText' button clicked."); // Will always be '开始' now
    if (_connectivityResult == ConnectivityResult.none) {
      addLog("MainPage: Start run validation failed - No internet connection.");
      _showNoInternetSnackbar();
      return;
    }
    if (_selectedAccountName == '新建') {
      addLog("MainPage: Start run validation failed - Account not selected ('新建').");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个有效的账户或新建账户。')),
      );
      return;
    }
    if ((_selectedMinutes == null || _selectedSeconds == null || _kmController.text.isEmpty || _selectedCount == null)) {
      addLog("MainPage: Start run validation failed - Parameters not fully set. M: $_selectedMinutes, S: $_selectedSeconds, KM: ${_kmController.text}, Count: $_selectedCount");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写完整的跑步参数。')),
      );
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final selectedAccount = _selectedAccountName == '新建' || appState.accountsList.isEmpty
        ? null
        : appState.accountsList.firstWhere((acc) => acc['name'] == _selectedAccountName, orElse: () => {'userid': ''});

    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('run_details_userId_for_new_run', appState.currentUserId ?? '');
      prefs.setDouble('run_details_distanceKm_for_new_run', double.tryParse(_kmController.text) ?? 1.0);
      prefs.remove('run_details_recordId');
      prefs.remove('run_details_currentCount');
      prefs.remove('run_details_remainingSeconds');
      prefs.remove('run_details_startTime');
    });

    addLog("MainPage: Navigating to ProgressPage. UserID: ${selectedAccount?['userid']}, M: $_selectedMinutes, S: $_selectedSeconds, KM: ${_kmController.text}, Count: $_selectedCount, QuickMode: $_isQuickCompleteMode, Resuming: false");
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProgressPage(
          userId: selectedAccount?['userid'],
          minutes: _selectedMinutes!,
          seconds: _selectedSeconds!,
          distanceKm: double.tryParse(_kmController.text) ?? 0.0,
          count: _selectedCount!,
          isQuickMode: _isQuickCompleteMode,
          isResuming: false, // Always false now
        ),
      ),
    );

    addLog("MainPage: Returned from ProgressPage with result: $result");
    if (mounted) {
      setState(() {
        _isRunInProgress = false;
        _startButtonText = '开始';
      });
    }
  }

  Future<void> _confirmDeleteAccount(String accountNameToDelete) async {
    addLog("MainPage: Delete button clicked for account: '$accountNameToDelete'.");
    if (accountNameToDelete == '新建') {
      addLog("MainPage: Attempt to delete '新建' account aborted.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\'新建\' 账号不能被删除。')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text('您确定要删除账号 "$accountNameToDelete" 吗？此操作无法撤销。'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop(false);
                addLog("MainPage: Delete confirmation for '$accountNameToDelete' cancelled by user.");
              },
            ),
            TextButton(
              child: const Text('删除', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop(true);
                addLog("MainPage: Delete confirmation for '$accountNameToDelete' confirmed by user.");
              },
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _performDeleteAccount(accountNameToDelete);
    }
  }

  Future<void> _performDeleteAccount(String accountNameToDelete) async {
    addLog("MainPage: Performing delete for account: '$accountNameToDelete'.");
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.removeAccount(accountNameToDelete);

    if (_selectedAccountName == accountNameToDelete) {
      addLog("MainPage: Deleted account '$accountNameToDelete' was the currently selected one. Resetting selection to '新建'.");
      setState(() {
        _selectedAccountName = '新建';
      });
      appState.setCurrentUserId(null);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_selected_account_name', '新建');
      addLog("MainPage: Updated 'last_selected_account_name' in SharedPreferences to '新建'.");
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('账号 "$accountNameToDelete" 已删除。')),
    );
    addLog("MainPage: Account '$accountNameToDelete' successfully deleted and UI updated.");
    _savePersistedData();
  }

  Widget _buildAccountDropdown(AppState appState) {
    List<DropdownMenuItem<String>> items = [
      const DropdownMenuItem(value: '新建', child: Text('新建')),
      ...appState.accountsList.map<DropdownMenuItem<String>>((Map<String, String> account) {
        return DropdownMenuItem<String>(
          value: account['name'],
          child: Text(account['name']!),
        );
      }).toList(),
    ];

    bool isValidSelection = items.any((item) => item.value == _selectedAccountName);
    String dropdownValue = _selectedAccountName;

    if (!isValidSelection) {
      addLog("MainPage: Current _selectedAccountName '$_selectedAccountName' is not in the valid items list. Setting dropdown to '新建' for current build and scheduling state update.");
      dropdownValue = '新建'; // Use '新建' for the DropdownButtonFormField's value in this build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          bool needsStateUpdate = false;
          if (_selectedAccountName != '新建') {
            _selectedAccountName = '新建';
            needsStateUpdate = true;
          }
          // Ensure AppState's currentUserId is also cleared if it's not already.
          if (appState.currentUserId != null) {
            appState.setCurrentUserId(null);
          }
          if (needsStateUpdate) {
            setState(() {}); // Update UI for _selectedAccountName change
          }
        }
      });
    }

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: '选择账户',
              border: OutlineInputBorder(),
            ),
            value: dropdownValue, // Use the potentially corrected dropdownValue
            items: items,
            onChanged: (String? newValue) {
              _handleAccountChanged(newValue, appState);
            },
          ),
        ),
        if (_selectedAccountName != '新建' && isValidSelection) // Also check isValidSelection to be safe
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: '删除账号 $_selectedAccountName',
            onPressed: () {
              _confirmDeleteAccount(_selectedAccountName);
            },
          ),
      ],
    );
  }

  void _handleAccountChanged(String? newValue, AppState appState) {
    if (newValue == null) return;
    addLog("MainPage: Account selection changed to: '$newValue'.");
    setState(() {
      _selectedAccountName = newValue;
      if (newValue == '新建') {
        appState.setCurrentUserId(null);
        addLog("MainPage: '新建' selected, currentUserId set to null.");
        _navigateToWindow2();
      } else {
        final selectedAccount = appState.accountsList.firstWhere(
          (acc) => acc['name'] == newValue,
          orElse: () => <String, String>{},
        );
        if (selectedAccount.isNotEmpty) {
          appState.setCurrentUserId(selectedAccount['userid']);
          Clipboard.setData(ClipboardData(text: selectedAccount['userid']!));
          addLog("MainPage: Account '${selectedAccount['name']}' selected. UserID '${selectedAccount['userid']}' set and copied to clipboard.");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('账号ID: ${selectedAccount['userid']} 已复制到剪贴板')),
          );
        } else {
          addLog("MainPage: Selected account '$newValue' not found in AppState list (should not happen).");
          appState.setCurrentUserId(null);
        }
      }
    });
    _savePersistedData();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SHNU跑步助手'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '帮助与日志',
            onPressed: _navigateToHelpPage,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildAccountDropdown(appState),
              const SizedBox(height: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          child: DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            ),
                            hint: const Text('分'),
                            value: _selectedMinutes,
                            items: List.generate(25, (index) => index + 1)
                                .map((minute) => DropdownMenuItem(
                                      value: minute,
                                      child: Text(minute.toString()),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedMinutes = value;
                              });
                              _savePersistedData();
                            },
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6.0),
                          child: Text('分', style: TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 80,
                          child: DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            ),
                            hint: const Text('秒'),
                            value: _selectedSeconds,
                            items: List.generate(60, (index) => index)
                                .map((second) => DropdownMenuItem(
                                      value: second,
                                      child: Text(second.toString()),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedSeconds = value;
                              });
                              _savePersistedData();
                            },
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6.0),
                          child: Text('秒', style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _kmController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            onChanged: (_) => _savePersistedData(),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6.0),
                          child: Text('km', style: TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 80,
                          child: DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            ),
                            hint: const Text('次'),
                            value: _selectedCount,
                            items: List.generate(20, (index) => index + 1)
                                .map((count) => DropdownMenuItem(
                                      value: count,
                                      child: Text(count.toString()),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedCount = value;
                              });
                              _savePersistedData();
                            },
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6.0),
                          child: Text('次', style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('快速完成模式', style: TextStyle(fontSize: 16)),
                        Checkbox(
                          value: _isQuickCompleteMode,
                          onChanged: (bool? value) {
                            setState(() {
                              _isQuickCompleteMode = value ?? false;
                            });
                            _savePersistedData();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                      onPressed: () {
                        _navigateToProgressPage();
                      },
                      child: Text(_startButtonText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
