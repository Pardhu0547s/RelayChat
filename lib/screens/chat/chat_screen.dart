import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/bluetooth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/colors.dart';
import '../../utils/constants.dart';
import '../../widgets/message_box.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/status_badge.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<bool>? _disconnectSub;
  DiscoveredUser? _targetUser;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    _disconnectSub = btProvider.deviceDisconnected.listen((_) {
      if (mounted) {
        Navigator.popUntil(context, ModalRoute.withName(AppConstants.routeScanner));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device disconnected unexpectedly.')),
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is DiscoveredUser) {
        _targetUser = args;
      }
      _isInit = true;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _disconnectSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final targetName = _targetUser?.name ?? 'Broadcast Channel';
    final targetId = _targetUser?.phoneId ?? 'BROADCAST';

    final textPrimary = AppColors.getTextPrimary(context);
    final cardBg = AppColors.getCard(context);
    final background = AppColors.getBackground(context);
    final subtitleColor = AppColors.getSubtitle(context);
    final dividerColor = AppColors.getDivider(context);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 1,
        shadowColor: Colors.black26,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              targetName,
              style: TextStyle(
                color: textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                StatusBadge(
                  label: targetId,
                  isPositive: true,
                ),
                const SizedBox(width: 8),
                const StatusBadge(
                  label: 'Encryption: Off',
                  customIcon: Icons.lock_outline,
                  customColor: AppColors.secondary,
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Send SOS',
            icon: const Icon(Icons.warning_rounded, color: Colors.redAccent),
            onPressed: () {
              Provider.of<ChatProvider>(context, listen: false)
                  .sendMessage('', 'BROADCAST', isSos: true);
            },
          ),
          IconButton(
            tooltip: 'Toggle Light / Dark Mode',
            icon: Icon(
              themeProvider.isDarkMode
                  ? Icons.wb_sunny_rounded
                  : Icons.nightlight_round,
              color: themeProvider.isDarkMode
                  ? Colors.amber
                  : AppColors.primary,
            ),
            onPressed: () {
              themeProvider.toggleTheme();
            },
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: textPrimary),
            color: cardBg,
            onSelected: (value) {
              if (value == 'clear') {
                Provider.of<ChatProvider>(context, listen: false).clearChat();
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem<String>(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Text('Clear Chat', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          _scrollToBottom();
          final messages = chatProvider.getMessagesForUser(targetId);

          return Column(
            children: [
              // Messages Header Bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: background,
                child: Center(
                  child: Text(
                    'Private Chat',
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              Divider(color: dividerColor, height: 1),

              // Chat Messages List
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet. Say hi to $targetName!',
                          style: TextStyle(color: subtitleColor),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          return MessageBubble(message: message);
                        },
                      ),
              ),

              // Future-Proof Input Bar (📎 Message... 🎤 ➤)
              MessageBox(
                onSend: (text) {
                  chatProvider.sendMessage(text, targetId);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
