import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../main.dart'; // For AppState
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

// Define the FFI signature for the C++ function
// extern "C" __declspec(dllexport) const char* fetch_user_id();
typedef FetchUserIdNative = ffi.Pointer<Utf8> Function();
typedef FetchUserIdDart = ffi.Pointer<Utf8> Function();

class NewAccountPage extends StatefulWidget {
  const NewAccountPage({super.key});

  @override
  State<NewAccountPage> createState() => _NewAccountPageState();
}

class _NewAccountPageState extends State<NewAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();

  String _getUserIdFunction() {
    print("获取按钮被点击，尝试通过FFI调用原生C++函数 fetch_user_id");
    try {
      // Load the executable (the Flutter app itself, since the C++ code is statically linked)
      final dylib = ffi.DynamicLibrary.executable();

      // Look up the function
      final FetchUserIdDart fetchUserId =
          dylib.lookupFunction<FetchUserIdNative, FetchUserIdDart>('fetch_user_id');

      // Call the function
      final ffi.Pointer<Utf8> userIdPtr = fetchUserId();

      if (userIdPtr.address == 0) {
        print("原生函数返回了空指针。");
        return "";
      }
      print("get");
      // Convert the C string to a Dart string
      final String userId = userIdPtr.toDartString();
      
      // Important: The C++ code uses a static buffer. We don't need to free userIdPtr here
      // as it points to static memory in C++, not memory allocated by Dart FFI's allocator.
      // If the C++ code returned a malloc'd string, we would need to call free(userIdPtr).

      print("通过FFI获取到的User ID: '$userId'");
      return userId;
    } catch (e) {
      print("调用FFI函数 fetch_user_id 时发生错误: $e");
      // Show a more specific error to the user if needed, or log it.
      // For now, return empty string to trigger the existing dialog.
      return "";
    }
  }

  void _handleGetUserId() {
    String fetchedUserId = _getUserIdFunction();
    if (fetchedUserId.isEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 10),
                Text('获取失败'),
              ],
            ),
            content: const Text('请先确保电脑体锻打开微信小程序已打开且登陆。'),
            actions: <Widget>[
              TextButton(
                child: const Text('好的'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } else {
      setState(() {
        _userIdController.text = fetchedUserId;
      });
    }
  }

  Future<void> _saveAccount() async {
    if (_formKey.currentState!.validate()) {
      final String name = _nameController.text;
      final String userId = _userIdController.text;

      if (name.isEmpty || userId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备注和账号ID不能为空！')),
        );
        return;
      }

      final newAccount = {'name': name, 'userid': userId};
      print('保存账户: $newAccount');

      // Access AppState to add the account
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.addAccount(newAccount);
      
      print('账户已添加到 AppState');

      // Clear fields after saving
      _nameController.clear();
      _userIdController.clear();
      
      print('输入框已清空');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('账户已保存!')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _userIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建账号'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 第一行: 备注
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入备注';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // 第二行: 账号ID 和 获取按钮
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _userIdController,
                      decoration: const InputDecoration(
                        labelText: '账号ID',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入或获取账号ID';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _handleGetUserId,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), // Adjust padding for button height
                    ),
                    child: const Text('获取'),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // 第三行: 保存按钮
              ElevatedButton(
                onPressed: _saveAccount,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
