import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

Future<void> showCommLinkDialog(
  BuildContext context, {
  EarthApi api = const EarthApi(),
  EarthState? state,
  String? initialChannelId,
  bool initialDispatchMode = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
        child: CommLinkDialog(
          api: api,
          state: state,
          initialChannelId: initialChannelId,
          initialDispatchMode: initialDispatchMode,
        ),
      ),
    ),
  );
}

class CommLinkDialog extends StatefulWidget {
  final EarthApi api;
  final EarthState? state;
  final String? initialChannelId;
  final bool initialDispatchMode;

  const CommLinkDialog({
    super.key,
    this.api = const EarthApi(),
    this.state,
    this.initialChannelId,
    this.initialDispatchMode = false,
  });

  @override
  State<CommLinkDialog> createState() => _CommLinkDialogState();
}

class _CommLinkDialogState extends State<CommLinkDialog> {
  // Mode: 0 = Frequency Channels, 1 = Diplomatic Dispatch
  int _currentMode = 0;

  // Channels State
  List<Map<String, dynamic>> _channels = [];
  String _selectedChannelId = 'channel-global-relay';
  List<Map<String, dynamic>> _messages = [];
  final TextEditingController _msgInputController = TextEditingController();
  final ScrollController _msgScrollController = ScrollController();

  // Dispatches State
  String _dispatchFolder = 'inbox'; // inbox, sent, compose
  List<Map<String, dynamic>> _dispatches = [];
  Map<String, dynamic>? _selectedDispatch;
  int _unreadDispatchesCount = 0;

  // Compose State
  final TextEditingController _composeRecipientController = TextEditingController();
  final TextEditingController _composeSubjectController = TextEditingController();
  final TextEditingController _composeBodyController = TextEditingController();
  String _composeType = 'diplomatic';

  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialDispatchMode ? 1 : 0;
    if (widget.initialChannelId != null) {
      _selectedChannelId = widget.initialChannelId!;
    }
    _initialLoad();
  }

  @override
  void dispose() {
    _msgInputController.dispose();
    _msgScrollController.dispose();
    _composeRecipientController.dispose();
    _composeSubjectController.dispose();
    _composeBodyController.dispose();
    super.dispose();
  }

  Future<void> _initialLoad() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final channelsRaw = await widget.api.commChannels();
      final channels = channelsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (channels.isNotEmpty && !channels.any((c) => c['id'] == _selectedChannelId)) {
        _selectedChannelId = channels.first['id'] as String;
      }

      final messagesRaw = await widget.api.commMessages(channelId: _selectedChannelId);
      final messages = messagesRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final dispatchesRes = await widget.api.commDispatches(folder: _dispatchFolder);
      final dispatchesRaw = dispatchesRes['dispatches'] as List<dynamic>? ?? const [];
      final dispatches = dispatchesRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final unreadCount = _parseNumber(dispatchesRes['unreadCount']);

      if (mounted) {
        setState(() {
          _channels = channels;
          _messages = messages;
          _dispatches = dispatches;
          _unreadDispatchesCount = unreadCount;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectChannel(String channelId) async {
    setState(() {
      _selectedChannelId = channelId;
      _loading = true;
    });
    try {
      final messagesRaw = await widget.api.commMessages(channelId: channelId);
      final messages = messagesRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) {
        setState(() {
          _messages = messages;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgInputController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final res = await widget.api.sendCommMessage(
        channelId: _selectedChannelId,
        body: text,
      );
      _msgInputController.clear();
      final newMsg = res['message'] as Map<String, dynamic>?;
      if (newMsg != null && mounted) {
        setState(() {
          _messages.add(Map<String, dynamic>.from(newMsg));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _fetchDispatches(String folder) async {
    setState(() {
      _dispatchFolder = folder;
      _selectedDispatch = null;
      _loading = true;
    });
    try {
      final res = await widget.api.commDispatches(folder: folder);
      final raw = res['dispatches'] as List<dynamic>? ?? const [];
      final list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final unreadCount = _parseNumber(res['unreadCount']);
      if (mounted) {
        setState(() {
          _dispatches = list;
          _unreadDispatchesCount = unreadCount;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _openDispatch(Map<String, dynamic> dispatch) async {
    setState(() => _selectedDispatch = dispatch);
    if (dispatch['status'] == 'unread') {
      try {
        await widget.api.markCommDispatchRead(dispatch['id'] as String);
        setState(() {
          dispatch['status'] = 'read';
          if (_unreadDispatchesCount > 0) _unreadDispatchesCount--;
        });
      } catch (_) {}
    }
  }

  Future<void> _sendDispatch() async {
    final recipient = _composeRecipientController.text.trim();
    final subject = _composeSubjectController.text.trim();
    final body = _composeBodyController.text.trim();

    if (recipient.isEmpty || subject.isEmpty || body.isEmpty || _sending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out Recipient, Subject, and Message body.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.api.sendCommDispatch(
        recipientId: recipient,
        subject: subject,
        body: body,
        dispatchType: _composeType,
      );
      _composeRecipientController.clear();
      _composeSubjectController.clear();
      _composeBodyController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Diplomatic dispatch transmitted successfully!'),
            backgroundColor: EarthColors.cyanAccent,
          ),
        );
        _fetchDispatches('sent');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dispatch failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_msgScrollController.hasClients) {
        _msgScrollController.animateTo(
          _msgScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EarthColors.cyanAccent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: EarthColors.cyanAccent.withAlpha(25),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            // Top App Bar / Mode Switcher
            _buildTopBar(),

            // Main Body (Mode 0: Channels, Mode 1: Dispatches)
            Expanded(
              child: _loading && _channels.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: EarthColors.cyanAccent),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Error: $_error', style: const TextStyle(color: Colors.redAccent)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _initialLoad,
                                style: ElevatedButton.styleFrom(backgroundColor: EarthColors.cyanAccent, foregroundColor: Colors.black),
                                child: const Text('RETRY'),
                              ),
                            ],
                          ),
                        )
                      : _currentMode == 0
                          ? _buildChannelsView()
                          : _buildDispatchesView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: EarthColors.cardSurface,
        border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.settings_input_antenna, color: EarthColors.cyanAccent, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UNIVERSAL COMM-LINK / SUB-SPACE RELAY',
                  style: TextStyle(
                    color: EarthColors.cyanAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  'Encrypted multi-spectrum civilizational frequency feeds & diplomatic dispatches.',
                  style: TextStyle(color: EarthColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),

          // Mode Tabs
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: EarthColors.panelSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: EarthColors.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _topTabButton(0, 'CHANNELS', Icons.chat_bubble_outline),
                const SizedBox(width: 2),
                _topTabButton(1, 'DISPATCHES', Icons.mail_outline, badge: _unreadDispatchesCount),
              ],
            ),
          ),
          const SizedBox(width: 12),

          IconButton(
            icon: const Icon(Icons.close, color: EarthColors.textMuted, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _topTabButton(int mode, String label, IconData icon, {int badge = 0}) {
    final isSelected = _currentMode == mode;
    return InkWell(
      onTap: () => setState(() => _currentMode = mode),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? EarthColors.cyanAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.black : EarthColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10.5,
                letterSpacing: 0.6,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : EarthColors.cyanAccent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    color: isSelected ? EarthColors.cyanAccent : Colors.black,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================
  // MODE 0: FREQUENCY CHANNELS
  // ==========================================

  Widget _buildChannelsView() {
    final currentChannel = _channels.firstWhere(
      (c) => c['id'] == _selectedChannelId,
      orElse: () => {
        'id': _selectedChannelId,
        'name': 'Active Channel',
        'description': '',
      },
    );

    return Row(
      children: [
        // Left Channel Drawer
        Container(
          width: 260,
          decoration: const BoxDecoration(
            color: EarthColors.cardSurface,
            border: Border(right: BorderSide(color: EarthColors.borderSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
                ),
                child: const Text(
                  'ACTIVE FREQUENCIES',
                  style: TextStyle(
                    color: EarthColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _channels.length,
                  itemBuilder: (ctx, i) {
                    final ch = _channels[i];
                    final isSelected = ch['id'] == _selectedChannelId;
                    final scope = ch['scope']?.toString() ?? 'global';
                    return InkWell(
                      onTap: () => _selectChannel(ch['id'] as String),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? EarthColors.cyanAccent.withAlpha(25) : Colors.transparent,
                          border: Border(
                            left: BorderSide(
                              color: isSelected ? EarthColors.cyanAccent : Colors.transparent,
                              width: 3,
                            ),
                            bottom: const BorderSide(color: EarthColors.borderSubtle, width: 0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(_getScopeIcon(scope), size: 14, color: isSelected ? EarthColors.cyanAccent : EarthColors.textMuted),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    ch['name']?.toString() ?? ch['id'].toString(),
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : EarthColors.textMuted,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 11.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (ch['description'] != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                ch['description'].toString(),
                                style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Right Message Stream & Input Box
        Expanded(
          child: Column(
            children: [
              // Channel Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: EarthColors.panelSurface,
                  border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
                ),
                child: Row(
                  children: [
                    Icon(_getScopeIcon(currentChannel['scope']?.toString() ?? 'global'), color: EarthColors.cyanAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentChannel['name']?.toString() ?? 'Channel',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          if (currentChannel['description'] != null)
                            Text(
                              currentChannel['description'].toString(),
                              style: const TextStyle(color: EarthColors.textMuted, fontSize: 10.5),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: EarthColors.cyanAccent.withAlpha(25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: EarthColors.cyanAccent.withAlpha(80)),
                      ),
                      child: const Text('LIVE FREQUENCY', style: TextStyle(color: EarthColors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

              // Message Stream
              Expanded(
                child: _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages on this frequency yet.\nTransmit the first broadcast below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: EarthColors.textMuted, fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        controller: _msgScrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) => _buildMessageBubble(_messages[i]),
                      ),
              ),

              // Message Input Box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: EarthColors.cardSurface,
                  border: Border(top: BorderSide(color: EarthColors.borderSubtle)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgInputController,
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Transmit message to #${currentChannel['name']}...',
                          hintStyle: const TextStyle(color: EarthColors.textMuted, fontSize: 12),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          filled: true,
                          fillColor: EarthColors.panelSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: EarthColors.borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: EarthColors.borderSubtle),
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _sendMessage,
                      icon: _sending
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.send, size: 16),
                      style: IconButton.styleFrom(
                        backgroundColor: EarthColors.cyanAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final senderName = msg['sender_display_name'] ?? msg['sender_human_id'] ?? 'Citizen';
    final dynasty = msg['sender_dynasty_name'];
    final body = msg['body'] ?? '';
    final day = _parseNumber(msg['game_day']);
    final min = _parseNumber(msg['game_minute']);
    final hour = (min ~/ 60).toString().padLeft(2, '0');
    final minute = (min % 60).toString().padLeft(2, '0');
    final attachments = msg['attachments'] as List<dynamic>? ?? const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: EarthColors.cyanAccent.withAlpha(40),
            child: const Icon(Icons.person, size: 14, color: EarthColors.cyanAccent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      senderName.toString(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                    if (dynasty != null && dynasty.toString().isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: violetColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: violetColor.withAlpha(100), width: 0.5),
                        ),
                        child: Text(
                          dynasty.toString(),
                          style: const TextStyle(color: violetColor, fontSize: 8.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      'Day $day · $hour:$minute',
                      style: const TextStyle(color: EarthColors.textMuted, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: EarthColors.cardSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: EarthColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        body.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      if (attachments.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: attachments.map((att) {
                            final map = att is Map ? att : {};
                            final title = map['title'] ?? map['id'] ?? 'Attached Record';
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: EarthColors.goldMetallic.withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: EarthColors.goldMetallic.withAlpha(100), width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.attachment, size: 12, color: EarthColors.goldMetallic),
                                  const SizedBox(width: 4),
                                  Text(
                                    title.toString(),
                                    style: const TextStyle(color: EarthColors.goldMetallic, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MODE 1: DIPLOMATIC DISPATCHES (MAIL)
  // ==========================================

  Widget _buildDispatchesView() {
    return Row(
      children: [
        // Left Sub-nav & Mail List
        Container(
          width: 320,
          decoration: const BoxDecoration(
            color: EarthColors.cardSurface,
            border: Border(right: BorderSide(color: EarthColors.borderSubtle)),
          ),
          child: Column(
            children: [
              // Folder Selector
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
                ),
                child: Row(
                  children: [
                    _folderButton('inbox', 'INBOX', Icons.inbox, badge: _unreadDispatchesCount),
                    const SizedBox(width: 4),
                    _folderButton('sent', 'SENT', Icons.send),
                    const SizedBox(width: 4),
                    _folderButton('compose', 'COMPOSE', Icons.edit),
                  ],
                ),
              ),

              // Mail List or Compose hint
              Expanded(
                child: _dispatchFolder == 'compose'
                    ? const Center(
                        child: Text(
                          'Fill out the form on the right\nto transmit a formal diplomatic dispatch.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: EarthColors.textMuted, fontSize: 11),
                        ),
                      )
                    : _dispatches.isEmpty
                        ? const Center(
                            child: Text(
                              'No dispatches in this folder.',
                              style: TextStyle(color: EarthColors.textMuted, fontSize: 12),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _dispatches.length,
                            itemBuilder: (ctx, i) {
                              final d = _dispatches[i];
                              final isSelected = _selectedDispatch?['id'] == d['id'];
                              final isUnread = d['status'] == 'unread';
                              final sender = d['sender_display_name'] ?? d['sender_human_id'] ?? 'Diplomat';
                              final recipient = d['recipient_display_name'] ?? d['recipient_human_id'] ?? 'Recipient';
                              final subject = d['subject'] ?? 'No Subject';
                              final type = d['dispatch_type']?.toString() ?? 'diplomatic';

                              return InkWell(
                                onTap: () => _openDispatch(d),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? EarthColors.cyanAccent.withAlpha(25)
                                        : (isUnread ? EarthColors.panelSurface : Colors.transparent),
                                    border: Border(
                                      left: BorderSide(
                                        color: isUnread ? EarthColors.cyanAccent : Colors.transparent,
                                        width: 3,
                                      ),
                                      bottom: const BorderSide(color: EarthColors.borderSubtle, width: 0.5),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            isUnread ? Icons.mark_email_unread : Icons.drafts,
                                            size: 14,
                                            color: isUnread ? EarthColors.cyanAccent : EarthColors.textMuted,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              _dispatchFolder == 'sent' ? 'To: $recipient' : 'From: $sender',
                                              style: TextStyle(
                                                color: isUnread ? Colors.white : EarthColors.textMuted,
                                                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                                fontSize: 11,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          _buildDispatchTypeBadge(type),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        subject.toString(),
                                        style: TextStyle(
                                          color: isUnread ? Colors.white : EarthColors.textMuted,
                                          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 11.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),

        // Right View: Either Dispatch Reader or Compose Form
        Expanded(
          child: _dispatchFolder == 'compose'
              ? _buildComposeForm()
              : (_selectedDispatch != null
                  ? _buildDispatchReader(_selectedDispatch!)
                  : const Center(
                      child: Text(
                        'Select a dispatch from the list to view.',
                        style: TextStyle(color: EarthColors.textMuted, fontSize: 12),
                      ),
                    )),
        ),
      ],
    );
  }

  Widget _folderButton(String folderKey, String label, IconData icon, {int badge = 0}) {
    final isSelected = _dispatchFolder == folderKey;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (folderKey == 'compose') {
            setState(() {
              _dispatchFolder = 'compose';
              _selectedDispatch = null;
            });
          } else {
            _fetchDispatches(folderKey);
          }
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected ? EarthColors.cyanAccent : EarthColors.panelSurface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: isSelected ? Colors.black : Colors.white),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 9.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.black : EarthColors.cyanAccent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      color: isSelected ? EarthColors.cyanAccent : Colors.black,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDispatchReader(Map<String, dynamic> dispatch) {
    final sender = dispatch['sender_display_name'] ?? dispatch['sender_human_id'] ?? 'Sender';
    final dynasty = dispatch['sender_dynasty_name'];
    final recipient = dispatch['recipient_display_name'] ?? dispatch['recipient_human_id'] ?? 'Recipient';
    final subject = dispatch['subject'] ?? 'No Subject';
    final body = dispatch['body'] ?? '';
    final day = _parseNumber(dispatch['game_day']);
    final min = _parseNumber(dispatch['game_minute']);
    final type = dispatch['dispatch_type']?.toString() ?? 'diplomatic';
    final payload = dispatch['action_payload'] is Map ? Map<String, dynamic>.from(dispatch['action_payload'] as Map) : {};

    return Container(
      padding: const EdgeInsets.all(20),
      color: EarthColors.panelSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EarthColors.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EarthColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDispatchTypeBadge(type),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Game Day $day · ${min ~/ 60}:${(min % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(color: EarthColors.textMuted, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  subject.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text('FROM: ', style: TextStyle(color: EarthColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                    Text('$sender ', style: const TextStyle(color: EarthColors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    if (dynasty != null)
                      Text('($dynasty) ', style: const TextStyle(color: violetColor, fontSize: 10.5)),
                    const SizedBox(width: 12),
                    const Text('TO: ', style: TextStyle(color: EarthColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                    Text('$recipient', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Message Body
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EarthColors.cardSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: EarthColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      body.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
                    ),

                    // Actionable Payload Card
                    if (payload.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: EarthColors.goldMetallic.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: EarthColors.goldMetallic.withAlpha(100)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.assignment_turned_in, color: EarthColors.goldMetallic, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('ATTACHED FORMAL TERMS', style: TextStyle(color: EarthColors.goldMetallic, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  Text(
                                    payload.entries.map((e) => '${e.key}: ${e.value}').join(' | '),
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Action executed for: ${payload.values.firstOrNull}')),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: EarthColors.goldMetallic,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                              child: const Text('REVIEW TERMS'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposeForm() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TRANSMIT DIPLOMATIC DISPATCH',
            style: TextStyle(
              color: EarthColors.cyanAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),

          // Recipient & Type Row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _composeRecipientController,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Recipient ID / Name (e.g. H-0012)',
                    labelStyle: TextStyle(color: EarthColors.textMuted, fontSize: 12),
                    filled: true,
                    fillColor: EarthColors.cardSurface,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: _composeType,
                  isExpanded: true,
                  dropdownColor: EarthColors.cardSurface,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Dispatch Type',
                    labelStyle: TextStyle(color: EarthColors.textMuted, fontSize: 12),
                    filled: true,
                    fillColor: EarthColors.cardSurface,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'diplomatic', child: Text('Diplomatic')),
                    DropdownMenuItem(value: 'contract_offer', child: Text('Contract Offer')),
                    DropdownMenuItem(value: 'patent_license', child: Text('Patent License')),
                    DropdownMenuItem(value: 'merger_tender', child: Text('Merger Tender')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _composeType = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Subject
          TextField(
            controller: _composeSubjectController,
            style: const TextStyle(fontSize: 12, color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Subject',
              labelStyle: TextStyle(color: EarthColors.textMuted, fontSize: 12),
              filled: true,
              fillColor: EarthColors.cardSurface,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          // Body
          Expanded(
            child: TextField(
              controller: _composeBodyController,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                labelText: 'Formal Dispatch Body',
                labelStyle: TextStyle(color: EarthColors.textMuted, fontSize: 12),
                hintText: 'State diplomatic terms, bilateral proposals, or contract stipulations...',
                hintStyle: TextStyle(color: EarthColors.textMuted, fontSize: 12),
                filled: true,
                fillColor: EarthColors.cardSurface,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action Button
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _sendDispatch,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.send, size: 16),
              label: const Text('TRANSMIT DISPATCH'),
              style: ElevatedButton.styleFrom(
                backgroundColor: EarthColors.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDispatchTypeBadge(String type) {
    Color color = EarthColors.cyanAccent;
    String label = 'DIPLOMATIC';

    if (type == 'contract_offer') {
      color = EarthColors.goldMetallic;
      label = 'CONTRACT';
    } else if (type == 'patent_license') {
      color = violetColor;
      label = 'PATENT';
    } else if (type == 'merger_tender') {
      color = Colors.orangeAccent;
      label = 'MERGER';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withAlpha(100), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold),
      ),
    );
  }

  IconData _getScopeIcon(String scope) {
    switch (scope) {
      case 'city':
        return Icons.location_city;
      case 'institution':
        return Icons.corporate_fare;
      case 'direct':
        return Icons.lock;
      case 'global':
      default:
        return Icons.public;
    }
  }

  static int _parseNumber(dynamic val) {
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? double.tryParse(val)?.toInt() ?? 0;
    return 0;
  }
}
