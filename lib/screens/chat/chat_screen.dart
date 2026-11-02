import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/bluetooth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/colors.dart';
import '../../utils/constants.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/message_box.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/user_avatar.dart';

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
    final targetName = _targetUser?.name ?? 'Public Mesh Broadcast';
    final isBroadcast = _targetUser == null;

    final textPrimary = AppColors.getTextPrimary(context);
    final cardBg = AppColors.getCard(context);
    final background = AppColors.getBackground(context);
    final subtitleColor = AppColors.getSubtitle(context);
    final dividerColor = AppColors.getDivider(context);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0.5,
        shadowColor: Colors.black12,
        leadingWidth: 40,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            if (isBroadcast)
              const BrandLogo(size: 34, showGlow: true)
            else
              UserAvatar(
                name: targetName,
                isOnline: true,
                size: 34,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    targetName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isBroadcast ? AppColors.secondary : AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          isBroadcast
                              ? 'Off-Grid Mesh • All nodes'
                              : 'Connected via ESP-NOW Mesh',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Sleek SOS Emergency Action Pill
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Material(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Provider.of<ChatProvider>(context, listen: false)
                      .sendMessage('', 'BROADCAST', isSos: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.white),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('🚨 SOS Alert Broadcasted to All Mesh Nodes!'),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.redAccent,
                      duration: Duration(seconds: 4),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 15),
                      const SizedBox(width: 4),
                      const Text(
                        'SOS',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Toggle Theme',
            icon: Icon(
              themeProvider.isDarkMode
                  ? Icons.wb_sunny_rounded
                  : Icons.nightlight_round,
              size: 20,
              color: themeProvider.isDarkMode
                  ? Colors.amber
                  : AppColors.primary,
            ),
            onPressed: () => themeProvider.toggleTheme(),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: textPrimary),
            color: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                      SizedBox(width: 10),
                      Text('Clear Chat', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ];
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          _scrollToBottom();
          // Broadcast Channel has no target user: use the BROADCAST sentinel (never null / '').
          final String targetId = _targetUser?.phoneId ?? 'BROADCAST';
          final messages = chatProvider.getMessagesForUser(targetId);
          final DiscoveredUser? currentUser = _targetUser == null
              ? null
              : chatProvider.discoveredUsers.firstWhere(
                  (u) => u.phoneId == targetId,
                  orElse: () => _targetUser!,
                );
          final double distance = currentUser?.distance ?? 0.0;

          return Column(
            children: [
              // Messages Header Bar
              // Messages Header Bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                color: background,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const StatusBadge(
                      label: 'ESP-NOW Mesh Active',
                      isPositive: true,
                    ),
                    if (distance > 0) ...[
                      const SizedBox(width: 8),
                      StatusBadge(
                        label: '≈ ${distance.toStringAsFixed(1)}m away',
                        customIcon: Icons.near_me_rounded,
                        customColor: AppColors.primary,
                      ),
                    ],
                  ],
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
                onSendVoice: (bytes) {
                  chatProvider.sendVoiceBytes(bytes, targetId);
                },
                onSendImage: (bytes) {
                  chatProvider.sendImageBytes(bytes, targetId);
                },
                onSendLocation: (locStr) {
                  chatProvider.sendLocation(locStr, targetId);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
