import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';
import '../contracts/supply_contracts_dialog.dart';

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
        constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 760),
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
  final bool isPageMode;
  final ValueChanged<String>? onNavigate;

  const CommLinkDialog({
    super.key,
    this.api = const EarthApi(),
    this.state,
    this.initialChannelId,
    this.initialDispatchMode = false,
    this.isPageMode = false,
    this.onNavigate,
  });

  @override
  State<CommLinkDialog> createState() => _CommLinkDialogState();
}

class _CommLinkDialogState extends State<CommLinkDialog> {
  Color get _groupSurface => EarthThemeController.instance.cardSurface;

  // Channels State
  List<Map<String, dynamic>> _channels = [];
  String _selectedChannelId = 'channel-global-relay';
  List<Map<String, dynamic>> _messages = [];
  final TextEditingController _msgInputController = TextEditingController();
  final ScrollController _msgScrollController = ScrollController();
  String _channelScopeFilter = 'all'; // all, global, city, institution

  // Dispatches State: 'inbox', 'sent', 'compose'
  String _dispatchFolder = 'inbox';
  String _dispatchTypeFilter = 'all'; // all, unread, diplomatic, contract_offer
  List<Map<String, dynamic>> _dispatches = [];
  Map<String, dynamic>? _selectedDispatch;
  int _unreadDispatchesCount = 0;

  // Compose State
  final TextEditingController _composeRecipientController =
      TextEditingController();
  final TextEditingController _composeSubjectController =
      TextEditingController();
  final TextEditingController _composeBodyController = TextEditingController();
  final TextEditingController _composeContractIdController =
      TextEditingController();
  String _composeType = 'diplomatic';

  bool _loading = true;
  bool _messagesLoading = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialDispatchMode) {
      _dispatchFolder = 'inbox';
    }
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
    _composeContractIdController.dispose();
    super.dispose();
  }

  Future<void> _initialLoad() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final channelsRaw = await widget.api.commChannels();
      final channels =
          channelsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (channels.isNotEmpty &&
          !channels.any((c) => c['id'] == _selectedChannelId)) {
        _selectedChannelId = channels.first['id'] as String;
      }

      final messagesRaw =
          await widget.api.commMessages(channelId: _selectedChannelId);
      final messages =
          messagesRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final dispatchesRes =
          await widget.api.commDispatches(folder: _dispatchFolder);
      final dispatchesRaw =
          dispatchesRes['dispatches'] as List<dynamic>? ?? const [];
      final dispatches = dispatchesRaw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
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
    if (_selectedChannelId == channelId && _messages.isNotEmpty) return;
    EarthAudioEngine.instance.playClick();
    setState(() {
      _selectedChannelId = channelId;
      _messagesLoading = true;
    });
    try {
      final messagesRaw = await widget.api.commMessages(channelId: channelId);
      final messages =
          messagesRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) {
        setState(() {
          _messages = messages;
          _messagesLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _messagesLoading = false;
        });
      }
    }
  }

  Future<void> _sendMessage([String? quickText]) async {
    final text = quickText ?? _msgInputController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final res = await widget.api.sendCommMessage(
        channelId: _selectedChannelId,
        body: text,
      );
      if (quickText == null) {
        _msgInputController.clear();
      }
      final newMsg = res['message'] as Map<String, dynamic>?;
      if (newMsg != null && mounted) {
        setState(() {
          _messages.add(Map<String, dynamic>.from(newMsg));
        });
        EarthAudioEngine.instance.playChime();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transmission failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _fetchDispatches(String folder) async {
    EarthAudioEngine.instance.playClick();
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
    EarthAudioEngine.instance.playClick();
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

  Future<void> _replyToDispatch(Map<String, dynamic> dispatch) async {
    final senderId = dispatch['sender_human_id']?.toString() ??
        dispatch['sender_display_name']?.toString() ??
        '';
    final subject = dispatch['subject']?.toString() ?? '';
    final replySubject = subject.startsWith('RE:') ? subject : 'RE: $subject';

    setState(() {
      _dispatchFolder = 'compose';
      _composeRecipientController.text = senderId;
      _composeSubjectController.text = replySubject;
      _composeType = dispatch['dispatch_type']?.toString() ?? 'diplomatic';
    });
    EarthAudioEngine.instance.playClick();
  }

  Future<void> _archiveDispatch(Map<String, dynamic> dispatch) async {
    try {
      await widget.api.archiveCommDispatch(dispatch['id'] as String);
      if (!mounted) return;
      await _fetchDispatches('inbox');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispatch archived.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Archive failed: $e')),
        );
      }
    }
  }

  Future<void> _sendDispatch() async {
    final recipient = _composeRecipientController.text.trim();
    final subject = _composeSubjectController.text.trim();
    final body = _composeBodyController.text.trim();
    final contractId = _composeContractIdController.text.trim();

    if (recipient.isEmpty || subject.isEmpty || body.isEmpty || _sending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please fill out Recipient, Subject, and Message body.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final terms = contractId.isNotEmpty
          ? <String, dynamic>{'contractId': contractId}
          : const <String, dynamic>{};
      await widget.api.sendCommDispatch(
        recipientId: recipient,
        subject: subject,
        body: body,
        dispatchType: _composeType,
        actionPayload: terms,
      );
      _composeRecipientController.clear();
      _composeSubjectController.clear();
      _composeBodyController.clear();
      _composeContractIdController.clear();

      if (mounted) {
        EarthAudioEngine.instance.playChime();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Diplomatic dispatch sent successfully!'),
            backgroundColor: cyanAccentColor,
          ),
        );
        setState(() {
          _dispatchFolder = 'sent';
        });
        _fetchDispatches('sent');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dispatch failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _channels.isEmpty && _dispatches.isEmpty) {
      return const SizedBox(
        height: 380,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.signal_cellular_connected_no_internet_4_bar,
                color: Colors.redAccent,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                'Comm-Link Relay Error: $_error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: _initialLoad,
                label: const Text('RECONNECT RELAY'),
                style: FilledButton.styleFrom(
                  backgroundColor: cyanAccentColor,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final channelsTopic = EarthSection(
      title: 'CHANNELS',
      showSurface: false,
      child: Container(
        height: 480,
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(context.radiusCard),
          border: Border.all(color: context.subtleBorderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildChannelsView(),
      ),
    );

    final dispatchesTopic = EarthSection(
      title: 'DIPLOMATIC DISPATCHES',
      showSurface: false,
      trailing: _unreadDispatchesCount > 0
          ? EarthBadge(
              label: '$_unreadDispatchesCount UNREAD',
              variant: EarthBadgeVariant.warning,
            )
          : null,
      child: Container(
        height: 520,
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(context.radiusCard),
          border: Border.all(color: context.subtleBorderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildDispatchesContainer(),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        channelsTopic,
        const SizedBox(height: 24),
        dispatchesTopic,
      ],
    );
  }

  // ==========================================
  // MODE 0: FREQUENCY CHANNELS (MASTER-DETAIL)
  // ==========================================

  Widget _buildChannelsView() {
    final filteredChannels = _channels.where((ch) {
      final scope = ch['scope']?.toString() ?? 'global';
      if (_channelScopeFilter != 'all' && scope != _channelScopeFilter) {
        return false;
      }
      return true;
    }).toList();

    final currentChannel = _channels.firstWhere(
      (c) => c['id'] == _selectedChannelId,
      orElse: () => {
        'id': _selectedChannelId,
        'name': 'Planetary Public Relay',
        'scope': 'global',
        'description': 'Universal sub-space broadcast channel',
      },
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Sidebar: Channels List & Filters
          SizedBox(
            width: 250,
            child: Container(
              decoration: BoxDecoration(
                color: _groupSurface,
                border: const Border(right: BorderSide(color: Colors.white12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Scope filter bar
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.white12)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _scopeFilterChip('all', 'ALL'),
                          const SizedBox(width: 4),
                          _scopeFilterChip('global', 'GLOBAL'),
                          const SizedBox(width: 4),
                          _scopeFilterChip('city', 'CITY'),
                          const SizedBox(width: 4),
                          _scopeFilterChip('institution', 'INSTITUTION'),
                        ],
                      ),
                    ),
                  ),

                  // Channels List
                  Expanded(
                    child: filteredChannels.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No matching channels found.',
                                style:
                                    TextStyle(color: mutedColor, fontSize: 11),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredChannels.length,
                            itemBuilder: (ctx, i) {
                              final ch = filteredChannels[i];
                              final isSelected = ch['id'] == _selectedChannelId;
                              final scope = ch['scope']?.toString() ?? 'global';
                              final name = ch['name']?.toString() ??
                                  ch['id']?.toString() ??
                                  'Channel';
                              final desc = ch['description']?.toString() ?? '';

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () =>
                                      _selectChannel(ch['id'] as String),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? cyanAccentColor.withValues(
                                              alpha: .12)
                                          : Colors.transparent,
                                      border: Border(
                                        left: BorderSide(
                                          color: isSelected
                                              ? cyanAccentColor
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                        bottom: const BorderSide(
                                            color: Colors.white12, width: 0.5),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          margin: const EdgeInsets.only(top: 2),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? cyanAccentColor.withValues(
                                                    alpha: .2)
                                                : Colors.white
                                                    .withValues(alpha: .05),
                                            borderRadius:
                                                BorderRadius.circular(5),
                                          ),
                                          child: Icon(
                                            _getScopeIcon(scope),
                                            size: 12,
                                            color: isSelected
                                                ? cyanAccentColor
                                                : mutedColor,
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? inkColor
                                                      : inkColor.withValues(
                                                          alpha: .85),
                                                  fontWeight: isSelected
                                                      ? FontWeight.w800
                                                      : FontWeight.w600,
                                                  fontSize: 11.5,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (desc.isNotEmpty) ...[
                                                const SizedBox(height: 1),
                                                Text(
                                                  desc,
                                                  style: const TextStyle(
                                                    color: mutedColor,
                                                    fontSize: 9.5,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Right Chat Area: Stream & Transmit Bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The selected channel is already identified in the left list.
                // Keep its detail header out of the reading area.
                Visibility(
                  visible: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _groupSurface,
                      border: const Border(bottom: BorderSide(color: Colors.white12)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getScopeIcon(
                              currentChannel['scope']?.toString() ?? 'global'),
                          color: cyanAccentColor,
                          size: 15,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      currentChannel['name']?.toString() ??
                                          'Channel',
                                      style: const TextStyle(
                                        color: inkColor,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _buildScopeBadge(
                                      currentChannel['scope']?.toString() ??
                                          'global'),
                                ],
                              ),
                              if (currentChannel['description'] != null &&
                                  currentChannel['description']
                                      .toString()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 1),
                                Text(
                                  currentChannel['description'].toString(),
                                  style: const TextStyle(
                                      color: mutedColor, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2.5),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF10B981).withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: .5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle,
                                  size: 5, color: Color(0xFF10B981)),
                              SizedBox(width: 4),
                              Text(
                                'LIVE RELAY',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.refresh,
                              size: 15, color: mutedColor),
                          tooltip: 'Refresh frequency',
                          onPressed: () => _selectChannel(_selectedChannelId),
                        ),
                      ],
                    ),
                  ),
                ),

                // Message Stream
                Expanded(
                  child: _messagesLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _messages.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.speaker_notes_off_outlined,
                                        size: 36,
                                        color:
                                            mutedColor.withValues(alpha: .5)),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'No transmissions on this frequency yet.',
                                      style: TextStyle(
                                          color: inkColor,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 3),
                                    const Text(
                                      'Send the first message using the console below.',
                                      style: TextStyle(
                                          color: mutedColor, fontSize: 10.5),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _msgScrollController,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              itemCount: _messages.length,
                              itemBuilder: (ctx, i) =>
                                  _buildModernMessageBubble(_messages[i]),
                            ),
                ),

                // Quick Prompt Chips & Transmit Box
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 5, 10, 7),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Input Bar
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _msgInputController,
                              style: const TextStyle(
                                  fontSize: 11.5, color: inkColor),
                              decoration: InputDecoration(
                                hintText:
                                    'Send message to #${currentChannel['name'] ?? 'relay'}...',
                                hintStyle: const TextStyle(
                                    color: mutedColor, fontSize: 11),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: .04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(7),
                                  borderSide:
                                      const BorderSide(color: Colors.white12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(7),
                                  borderSide:
                                      const BorderSide(color: Colors.white12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(7),
                                  borderSide:
                                      const BorderSide(color: cyanAccentColor),
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 7),
                          FilledButton.icon(
                            onPressed: _sending ? null : () => _sendMessage(),
                            icon: _sending
                                ? const SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.black))
                                : const Icon(Icons.send, size: 13),
                            label: const Text(
                              'SEND',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 10.5),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: cyanAccentColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 9),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(7)),
                            ),
                          ),
                        ],
                      ),
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

  Widget _scopeFilterChip(String scope, String label) {
    final isSelected = _channelScopeFilter == scope;
    return InkWell(
      onTap: () => setState(() => _channelScopeFilter = scope),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: isSelected
              ? cyanAccentColor.withValues(alpha: .2)
              : Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected ? cyanAccentColor : Colors.white12,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? cyanAccentColor : mutedColor,
            fontSize: 8.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildModernMessageBubble(Map<String, dynamic> msg) {
    final myId = widget.state?.human['id']?.toString() ?? 'H-0044';
    final senderHumanId = msg['sender_human_id']?.toString() ?? '';
    final isSelf = senderHumanId == myId;

    final senderName = msg['sender_display_name'] ??
        msg['sender_human_id'] ??
        'Citizen Diplomat';
    final house = (msg['sender_house_name'] ?? msg['sender_dynasty_name'])?.toString();
    final body = msg['body'] ?? '';
    final day = _parseNumber(msg['game_day']);
    final min = _parseNumber(msg['game_minute']);
    final timestamp = formatGameDateTime(day, min);
    final attachments = msg['attachments'] as List<dynamic>? ?? const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: isSelf
                ? cyanAccentColor.withValues(alpha: .25)
                : violetColor.withValues(alpha: .25),
            child: Icon(
              isSelf ? Icons.person : Icons.person_outline,
              size: 13,
              color: isSelf ? cyanAccentColor : violetColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        senderName.toString(),
                        style: TextStyle(
                          color: isSelf ? cyanAccentColor : inkColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (house != null && house.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: violetColor.withValues(alpha: .2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: violetColor.withValues(alpha: .6),
                              width: 0.6),
                        ),
                        child: Text(
                          house,
                          style: const TextStyle(
                            color: violetColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      timestamp,
                      style: const TextStyle(color: mutedColor, fontSize: 9.5),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelf
                        ? cyanAccentColor.withValues(alpha: .08)
                        : Colors.white.withValues(alpha: .05),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: isSelf
                          ? cyanAccentColor.withValues(alpha: .3)
                          : Colors.white12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        body.toString(),
                        style: const TextStyle(
                          color: inkColor,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                      if (attachments.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: attachments.map((att) {
                            final map = att is Map ? att : {};
                            final title = map['title'] ??
                                map['id'] ??
                                'Associated Record';
                            return InkWell(
                              onTap: () {
                                final contractId =
                                    map['contractId']?.toString();
                                if (contractId != null) {
                                  showSupplyContractsDialog(
                                    context,
                                    api: widget.api,
                                    state: widget.state,
                                    initialContractId: contractId,
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: EarthColors.goldMetallic
                                      .withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: EarthColors.goldMetallic
                                          .withValues(alpha: .6)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.attachment,
                                        size: 10,
                                        color: EarthColors.goldMetallic),
                                    const SizedBox(width: 3),
                                    Text(
                                      title.toString(),
                                      style: const TextStyle(
                                        color: EarthColors.goldMetallic,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
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
  // MODE 1: DIPLOMATIC DISPATCHES (CONTAINER)
  // ==========================================

  Widget _buildDispatchesContainer() {
    if (_dispatchFolder == 'compose') {
      return _buildComposeForm();
    }
    return _buildDispatchesMailbox();
  }

  Widget _buildDispatchesMailbox() {
    final filteredDispatches = _dispatches.where((d) {
      final status = d['status']?.toString() ?? 'read';
      final type = d['dispatch_type']?.toString() ?? 'diplomatic';

      if (_dispatchTypeFilter == 'unread' && status != 'unread') return false;
      if (_dispatchTypeFilter != 'all' &&
          _dispatchTypeFilter != 'unread' &&
          type != _dispatchTypeFilter) {
        return false;
      }
      return true;
    }).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Mail Drawer
          SizedBox(
            width: 250,
            child: Container(
              decoration: BoxDecoration(
                color: _groupSurface,
                border: const Border(right: BorderSide(color: Colors.white12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Folder Buttons Header
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.white12)),
                    ),
                    child: Row(
                      children: [
                        _folderButton('inbox', 'INBOX', Icons.inbox_outlined,
                            badge: _unreadDispatchesCount),
                        const SizedBox(width: 4),
                        _folderButton('sent', 'SENT', Icons.send_outlined),
                        const SizedBox(width: 4),
                        _folderButton(
                            'compose', 'COMPOSE', Icons.edit_outlined),
                      ],
                    ),
                  ),

                  // Filter Row
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.white12)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _dispatchTypeFilterChip('all', 'ALL'),
                          const SizedBox(width: 4),
                          _dispatchTypeFilterChip('unread', 'UNREAD'),
                          const SizedBox(width: 4),
                          _dispatchTypeFilterChip('diplomatic', 'DIPLOMATIC'),
                          const SizedBox(width: 4),
                          _dispatchTypeFilterChip(
                              'contract_offer', 'CONTRACTS'),
                        ],
                      ),
                    ),
                  ),

                  // Mail List
                  Expanded(
                    child: filteredDispatches.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inbox_outlined,
                                      size: 28,
                                      color: mutedColor.withValues(alpha: .4)),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'No dispatches found in this folder.',
                                    style: TextStyle(
                                        color: mutedColor, fontSize: 11),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredDispatches.length,
                            itemBuilder: (ctx, i) {
                              final d = filteredDispatches[i];
                              final isSelected =
                                  _selectedDispatch?['id'] == d['id'];
                              final isUnread = d['status'] == 'unread';
                              final sender = d['sender_display_name'] ??
                                  d['sender_human_id'] ??
                                  'Diplomat';
                              final recipient = d['recipient_display_name'] ??
                                  d['recipient_human_id'] ??
                                  'Recipient';
                              final subject = d['subject'] ?? 'No Subject';
                              final type = d['dispatch_type']?.toString() ??
                                  'diplomatic';

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _openDispatch(d),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? cyanAccentColor.withValues(
                                              alpha: .14)
                                          : (isUnread
                                              ? Colors.white
                                                  .withValues(alpha: .06)
                                              : Colors.transparent),
                                      border: Border(
                                        left: BorderSide(
                                          color: isUnread
                                              ? cyanAccentColor
                                              : (isSelected
                                                  ? cyanAccentColor
                                                  : Colors.transparent),
                                          width: 3,
                                        ),
                                        bottom: const BorderSide(
                                            color: Colors.white12, width: 0.5),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              isUnread
                                                  ? Icons.mark_email_unread
                                                  : Icons.drafts_outlined,
                                              size: 13,
                                              color: isUnread
                                                  ? cyanAccentColor
                                                  : mutedColor,
                                            ),
                                            const SizedBox(width: 5),
                                            Expanded(
                                              child: Text(
                                                _dispatchFolder == 'sent'
                                                    ? 'To: $recipient'
                                                    : 'From: $sender',
                                                style: TextStyle(
                                                  color: isUnread
                                                      ? inkColor
                                                      : mutedColor,
                                                  fontWeight: isUnread
                                                      ? FontWeight.w800
                                                      : FontWeight.w600,
                                                  fontSize: 10.5,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            _buildDispatchTypeBadge(type),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          subject.toString(),
                                          style: TextStyle(
                                            color: isUnread
                                                ? inkColor
                                                : inkColor.withValues(
                                                    alpha: .85),
                                            fontWeight: isUnread
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            fontSize: 11.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Right Reading Area
          Expanded(
            child: _selectedDispatch != null
                ? _buildDispatchReader(_selectedDispatch!)
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.drafts_outlined,
                              size: 40,
                              color: mutedColor.withValues(alpha: .4)),
                          const SizedBox(height: 10),
                          const Text(
                            'Select a diplomatic dispatch to review',
                            style: TextStyle(
                                color: inkColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Encrypted correspondence, trade terms, and multilateral accords appear here.',
                            style: TextStyle(color: mutedColor, fontSize: 10.5),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _dispatchTypeFilterChip(String type, String label) {
    final isSelected = _dispatchTypeFilter == type;
    return InkWell(
      onTap: () => setState(() => _dispatchTypeFilter = type),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? cyanAccentColor.withValues(alpha: .2)
              : Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected ? cyanAccentColor : Colors.white12,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? cyanAccentColor : mutedColor,
            fontSize: 8.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _folderButton(String folderKey, String label, IconData icon,
      {int badge = 0}) {
    final isSelected = _dispatchFolder == folderKey;
    return Expanded(
      child: Material(
        color: Colors.transparent,
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
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
            decoration: BoxDecoration(
              color: isSelected
                  ? cyanAccentColor.withValues(alpha: .2)
                  : Colors.white.withValues(alpha: .04),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? cyanAccentColor : Colors.white12,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 12, color: isSelected ? cyanAccentColor : mutedColor),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? inkColor : mutedColor,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 9.5,
                      letterSpacing: 0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 3),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: EarthColors.goldMetallic,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDispatchReader(Map<String, dynamic> dispatch) {
    final sender = dispatch['sender_display_name'] ??
        dispatch['sender_human_id'] ??
        'Sender';
    final house = (dispatch['sender_house_name'] ?? dispatch['sender_dynasty_name'])?.toString();
    final recipient = dispatch['recipient_display_name'] ??
        dispatch['recipient_human_id'] ??
        'Recipient';
    final subject = dispatch['subject'] ?? 'No Subject';
    final body = dispatch['body'] ?? '';
    final day = _parseNumber(dispatch['game_day']);
    final min = _parseNumber(dispatch['game_minute']);
    final timestamp = formatGameDateTime(day, min);
    final type = dispatch['dispatch_type']?.toString() ?? 'diplomatic';
    final payload = dispatch['action_payload'] is Map
        ? Map<String, dynamic>.from(dispatch['action_payload'] as Map)
        : {};

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _groupSurface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: EarthColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDispatchTypeBadge(type),
                    Row(
                      children: [
                        Text(
                          timestamp,
                          style: const TextStyle(
                              color: mutedColor, fontSize: 10.5),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.reply,
                              size: 15, color: cyanAccentColor),
                          tooltip: 'Reply to dispatch',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _replyToDispatch(dispatch),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.archive_outlined,
                              size: 15, color: cyanAccentColor),
                          tooltip: 'Archive dispatch',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _archiveDispatch(dispatch),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subject.toString(),
                  style: const TextStyle(
                    color: inkColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 3,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('FROM: ',
                            style: TextStyle(
                                color: mutedColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                        Text('$sender ',
                            style: const TextStyle(
                                color: cyanAccentColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800)),
                        if (house != null && house.isNotEmpty)
                          Text('($house)',
                              style: const TextStyle(
                                  color: violetColor, fontSize: 10)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('TO: ',
                            style: TextStyle(
                                color: mutedColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                        Text('$recipient',
                            style: const TextStyle(
                                color: inkColor, fontSize: 10.5)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Message Body & Attached terms
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _groupSurface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: EarthColors.borderSubtle),
                    ),
                    child: Text(
                      body.toString(),
                      style: const TextStyle(
                        color: inkColor,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),

                  // Actionable Payload Card
                  if (payload.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: EarthColors.goldMetallic.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color:
                                EarthColors.goldMetallic.withValues(alpha: .6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.assignment_turned_in,
                                  color: EarthColors.goldMetallic, size: 15),
                              SizedBox(width: 5),
                              Text(
                                'ATTACHED FORMAL TERMS',
                                style: TextStyle(
                                  color: EarthColors.goldMetallic,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            payload.entries
                                .map((e) => '${e.key}: ${e.value}')
                                .join(' | '),
                            style:
                                const TextStyle(color: inkColor, fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () {
                              final contractId =
                                  payload['contractId']?.toString();
                              showSupplyContractsDialog(
                                context,
                                api: widget.api,
                                state: widget.state,
                                initialContractId: contractId,
                              );
                            },
                            icon: const Icon(Icons.visibility, size: 13),
                            label: const Text('REVIEW TERMS'),
                            style: FilledButton.styleFrom(
                              backgroundColor: EarthColors.goldMetallic,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 10.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MODE 2: COMPOSE DIPLOMATIC DISPATCH
  // ==========================================

  Widget _buildComposeForm() {
    return Container(
      decoration: BoxDecoration(
        color: _groupSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.send_rounded, size: 15, color: cyanAccentColor),
                  SizedBox(width: 7),
                  Text(
                    'SEND DIPLOMATIC DISPATCH',
                    style: TextStyle(
                      color: cyanAccentColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.9,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () => setState(() => _dispatchFolder = 'inbox'),
                icon: const Icon(Icons.close, size: 13, color: mutedColor),
                label: const Text('CANCEL',
                    style: TextStyle(color: mutedColor, fontSize: 10.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Recipient & Type Row (TextField 0)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _composeRecipientController,
                  style: const TextStyle(fontSize: 11.5, color: inkColor),
                  decoration: InputDecoration(
                    labelText: 'Recipient ID / Name (e.g. H-0012)',
                    labelStyle:
                        const TextStyle(color: mutedColor, fontSize: 11),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: cyanAccentColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _composeType,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF141A24),
                  style: const TextStyle(fontSize: 11.5, color: inkColor),
                  decoration: InputDecoration(
                    labelText: 'Dispatch Type',
                    labelStyle:
                        const TextStyle(color: mutedColor, fontSize: 11),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'diplomatic', child: Text('Diplomatic')),
                    DropdownMenuItem(
                        value: 'contract_offer', child: Text('Contract Offer')),
                    DropdownMenuItem(
                        value: 'patent_license', child: Text('Patent License')),
                    DropdownMenuItem(
                        value: 'merger_tender', child: Text('Merger Tender')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _composeType = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Subject field
          TextField(
            controller: _composeSubjectController,
            style: const TextStyle(fontSize: 11.5, color: inkColor),
            decoration: InputDecoration(
              labelText: 'Subject',
              labelStyle: const TextStyle(color: mutedColor, fontSize: 11),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: Colors.white.withValues(alpha: .04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: const BorderSide(color: cyanAccentColor),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Body Field (TextField 2)
          Expanded(
            child: TextField(
              controller: _composeBodyController,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 11.5, color: inkColor),
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                labelText: 'Formal Dispatch Body',
                labelStyle: const TextStyle(color: mutedColor, fontSize: 11),
                hintText:
                    'State diplomatic terms, bilateral stipulations, or contract proposals...',
                hintStyle: const TextStyle(color: mutedColor, fontSize: 11),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(color: cyanAccentColor),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Optional Contract ID & Action Row (TextField 3)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composeContractIdController,
                  style: const TextStyle(fontSize: 11, color: inkColor),
                  decoration: InputDecoration(
                    labelText: 'Attach Contract ID (Optional, e.g. CTR-100)',
                    labelStyle:
                        const TextStyle(color: mutedColor, fontSize: 10),
                    prefixIcon: const Icon(Icons.attach_file,
                        size: 13, color: EarthColors.goldMetallic),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .03),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(7),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _sending ? null : _sendDispatch,
                icon: _sending
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.send_rounded, size: 13),
                label: const Text('SEND DISPATCH'),
                style: FilledButton.styleFrom(
                  backgroundColor: cyanAccentColor,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScopeBadge(String scope) {
    Color color = cyanAccentColor;
    if (scope == 'city') color = Colors.lightBlueAccent;
    if (scope == 'institution') color = violetColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: .6), width: 0.6),
      ),
      child: Text(
        scope.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDispatchTypeBadge(String type) {
    Color color = cyanAccentColor;
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: .7), width: 0.8),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800),
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
        return Icons.lock_outline;
      case 'global':
      default:
        return Icons.public;
    }
  }

  static int _parseNumber(dynamic val) {
    if (val is num) return val.toInt();
    if (val is String) {
      return int.tryParse(val) ?? double.tryParse(val)?.toInt() ?? 0;
    }
    return 0;
  }
}
