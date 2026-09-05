import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

Future<void> showCommLinkDialog(BuildContext context,
    {EarthApi api = const EarthApi(),
    EarthState? state,
    String? initialChannelId}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 760),
        child: CommLinkDialog(
            api: api, state: state, initialChannelId: initialChannelId),
      ),
    ),
  );
}

class CommLinkDialog extends StatefulWidget {
  final EarthApi api;
  final EarthState? state;
  final String? initialChannelId;
  final bool isPageMode;
  final bool? compact;
  final ValueChanged<String>? onNavigate;
  final VoidCallback? onClose;

  const CommLinkDialog({
    super.key,
    this.api = const EarthApi(),
    this.state,
    this.initialChannelId,
    this.isPageMode = false,
    this.compact,
    this.onNavigate,
    this.onClose,
  });

  static String? lastActiveChannelId;

  @override
  State<CommLinkDialog> createState() => _CommLinkDialogState();
}

class _CommLinkDialogState extends State<CommLinkDialog> {
  final _searchController = TextEditingController();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _userSearchResults = [];
  String _selectedChannelId = 'channel-global-relay';
  String _searchQuery = '';
  bool _loading = true;
  bool _messagesLoading = false;
  bool _searchingUsers = false;
  bool _sending = false;
  String? _error;
  bool _showMobileChat = false;
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _selectedChannelId = widget.initialChannelId ??
        CommLinkDialog.lastActiveChannelId ??
        _selectedChannelId;
    if (widget.initialChannelId != null) {
      _showMobileChat = true;
    }
    _loadChannels();
  }

  @override
  void didUpdateWidget(covariant CommLinkDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialChannelId != null &&
        widget.initialChannelId != oldWidget.initialChannelId &&
        widget.initialChannelId != _selectedChannelId) {
      _showMobileChat = true;
      _selectChannel(widget.initialChannelId!);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String _formatChannelName(String name) {
    if (name.endsWith(' Chat')) {
      return name.substring(0, name.length - 5);
    }
    return name;
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim();
    });

    _searchDebounce?.cancel();
    if (_searchQuery.isEmpty) {
      setState(() {
        _userSearchResults = [];
        _searchingUsers = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      final q = _searchQuery;
      if (q.length < 2) {
        if (mounted) setState(() => _userSearchResults = []);
        return;
      }
      if (mounted) setState(() => _searchingUsers = true);
      try {
        final response = await widget.api.socialDirectory(query: q);
        if (!mounted || _searchQuery != q) return;
        if (response['humans'] is List) {
          setState(() {
            _userSearchResults = (response['humans'] as List)
                .whereType<Map>()
                .map((v) => Map<String, dynamic>.from(v))
                .toList();
            _searchingUsers = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searchingUsers = false);
      }
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _userSearchResults = [];
      _searchingUsers = false;
    });
  }

  Future<void> _startDirectChat(Map<String, dynamic> user) async {
    final userId = user['id']?.toString() ?? '';
    if (userId.isEmpty) return;

    try {
      final response = await widget.api.openDirectConversation(userId);
      if (response['channel'] is Map && mounted) {
        final channel =
            Map<String, dynamic>.from(response['channel'] as Map);
        final channelId = channel['id']?.toString() ?? '';
        setState(() {
          _channels = [
            ..._channels.where((v) => v['id'] != channelId),
            channel,
          ];
        });
        _clearSearch();
        await _selectChannel(channelId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to open chat: ${_clean(e)}')));
      }
    }
  }

  Future<void> _loadChannels() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final channels = (await widget.api.commChannels())
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
      final candidateId = widget.initialChannelId ??
          CommLinkDialog.lastActiveChannelId ??
          _selectedChannelId;
      if (channels.isNotEmpty && channels.any((v) => v['id'] == candidateId)) {
        _selectedChannelId = candidateId;
      } else if (channels.isNotEmpty &&
          !channels.any((v) => v['id'] == _selectedChannelId)) {
        _selectedChannelId =
            channels.first['id']?.toString() ?? _selectedChannelId;
      }
      CommLinkDialog.lastActiveChannelId = _selectedChannelId;
      final messages =
          await widget.api.commMessages(channelId: _selectedChannelId);
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _messages = messages
            .whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        _loading = false;
      });
      _scrollToBottom(animate: false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _clean(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectChannel(String id) async {
    CommLinkDialog.lastActiveChannelId = id;
    if (_selectedChannelId == id && _messages.isNotEmpty) return;
    EarthAudioEngine.instance.playClick();
    setState(() {
      _selectedChannelId = id;
      _messagesLoading = true;
      _error = null;
    });
    try {
      final messages = await widget.api.commMessages(channelId: id);
      if (!mounted) return;
      setState(() {
        _messages = messages
            .whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        _messagesLoading = false;
      });
      _scrollToBottom(animate: false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _clean(e);
          _messagesLoading = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final result = await widget.api.sendCommMessage(
        channelId: _selectedChannelId,
        body: body,
      );
      final message = result['message'];
      _messageController.clear();
      if (message is Map && mounted) {
        setState(() => _messages.add(Map<String, dynamic>.from(message)));
        EarthAudioEngine.instance.playChime();
        _scrollToBottom(animate: false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Message failed: ${_clean(e)}'),
            backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
  void _scrollToBottom({bool animate = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          if (animate) {
            _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut);
          } else {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        }
      });

  IconData _channelIcon(String scope) {
    switch (scope) {
      case 'direct':
        return Icons.person_outline;
      case 'global':
        return Icons.public;
      case 'city':
        return Icons.location_city_outlined;
      case 'corporation':
        return Icons.business_outlined;
      case 'community':
        return Icons.groups_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _channels.isEmpty) {
      return const SizedBox(
          height: 380, child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _channels.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
        const SizedBox(height: 12),
        Text(_error!,
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        EarthButton(
            label: 'RECONNECT',
            variant: EarthButtonVariant.primary,
            icon: Icons.refresh,
            onPressed: _loadChannels),
      ]));
    }

    void handleClose() {
      if (widget.onClose != null) {
        widget.onClose!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else if (widget.onNavigate != null) {
        widget.onNavigate!('command');
      }
    }

    final containerHeight = widget.isPageMode ? double.infinity : 540.0;
    return Container(
      height: containerHeight,
      decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: widget.isPageMode
              ? BorderRadius.zero
              : BorderRadius.circular(context.radiusCard),
          border: widget.isPageMode
              ? null
              : Border.all(color: context.subtleBorderColor)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, constraints) {
        final isSmallScreen = widget.compact ?? (constraints.maxWidth < 680);
        if (isSmallScreen) {
          return _showMobileChat
              ? _buildRightPanel(
                  isSmallScreen: true,
                  onBack: () => setState(() => _showMobileChat = false),
                  onClose: handleClose,
                )
              : _buildLeftPanel(
                  isSmallScreen: true,
                  onChannelSelected: () =>
                      setState(() => _showMobileChat = true),
                  onClose: handleClose,
                );
        }
        final list = _buildLeftPanel(
          isSmallScreen: false,
          onClose: handleClose,
        );
        final conversation = _buildRightPanel(
          isSmallScreen: false,
          onClose: handleClose,
        );
        return Row(children: [
          SizedBox(width: 250, child: list),
          VerticalDivider(
              width: 1, thickness: 1, color: context.subtleBorderColor),
          Expanded(child: conversation),
        ]);
      }),
    );
  }

  Widget _buildLeftPanel({
    bool isSmallScreen = false,
    VoidCallback? onChannelSelected,
    VoidCallback? onClose,
  }) {
    return Container(
      color: context.panelColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isSmallScreen)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.subtleBorderColor),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('comm_link_close_button'),
                    icon: const Icon(Icons.close, size: 18),
                    color: context.mutedColor,
                    tooltip: 'Close messages',
                    onPressed: onClose,
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    key: const ValueKey('comm_link_search_toggle'),
                    icon: Icon(_showSearch ? Icons.search_off : Icons.search,
                        size: 18),
                    color:
                        _showSearch ? context.primaryColor : context.mutedColor,
                    tooltip: 'Search chats',
                    onPressed: () {
                      setState(() {
                        _showSearch = !_showSearch;
                        if (_showSearch) {
                          WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _searchFocusNode.requestFocus());
                        } else {
                          _clearSearch();
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.forum_outlined,
                      size: 18, color: context.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'COMMUNICATIONS',
                      style: context.bodyStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        letterSpacing: 1.0,
                        color: context.inkColor,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.subtleBorderColor),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('comm_link_close_button'),
                    icon: const Icon(Icons.close, size: 18),
                    color: context.mutedColor,
                    tooltip: 'Close messages',
                    onPressed: onClose,
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    key: const ValueKey('comm_link_search_toggle'),
                    icon: Icon(_showSearch ? Icons.search_off : Icons.search,
                        size: 18),
                    color:
                        _showSearch ? context.primaryColor : context.mutedColor,
                    tooltip: 'Search chats',
                    onPressed: () {
                      setState(() {
                        _showSearch = !_showSearch;
                        if (_showSearch) {
                          WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _searchFocusNode.requestFocus());
                        } else {
                          _clearSearch();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          if (_showSearch || _searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: EarthSearchInput(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                hintText: 'Search chats or users...',
                fontSize: 13,
                onChanged: _onSearchChanged,
                onClear: _clearSearch,
              ),
            ),
          Expanded(
            child: _searchQuery.isNotEmpty
                ? _buildSearchResults(onChannelSelected: onChannelSelected)
                : _buildChannelsList(onChannelSelected: onChannelSelected),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelsList({VoidCallback? onChannelSelected}) {
    if (_channels.isEmpty) {
      return Center(
        child: Text('No chats available',
            style: context.bodyStyle.copyWith(color: context.mutedColor)),
      );
    }
    return ListView.builder(
      itemCount: _channels.length,
      itemBuilder: (context, index) {
        final ch = _channels[index];
        final id = ch['id']?.toString() ?? '';
        final rawName = ch['name']?.toString() ?? 'Channel';
        final name = _formatChannelName(rawName);
        final scope = ch['scope']?.toString() ?? 'public';
        final isSelected = id == _selectedChannelId;

        return _buildChannelTile(
          name: name,
          icon: _channelIcon(scope),
          isSelected: isSelected,
          onTap: () {
            _selectChannel(id);
            onChannelSelected?.call();
          },
        );
      },
    );
  }

  Widget _buildSearchResults({VoidCallback? onChannelSelected}) {
    if (_searchingUsers) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredChannels = _channels.where((ch) {
      final name = ch['name']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    if (filteredChannels.isEmpty && _userSearchResults.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: context.bodyStyle.copyWith(color: context.mutedColor),
        ),
      );
    }

    return ListView(
      children: [
        if (filteredChannels.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'CHANNELS',
              style: context.widgetFooterStyle.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...filteredChannels.map((ch) {
            final id = ch['id']?.toString() ?? '';
            final rawName = ch['name']?.toString() ?? 'Channel';
            final name = _formatChannelName(rawName);
            final scope = ch['scope']?.toString() ?? 'public';
            return _buildChannelTile(
              name: name,
              icon: _channelIcon(scope),
              isSelected: id == _selectedChannelId,
              onTap: () {
                _clearSearch();
                _selectChannel(id);
                onChannelSelected?.call();
              },
            );
          }),
        ],
        if (_userSearchResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'USERS',
              style: context.widgetFooterStyle.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ..._userSearchResults.map((u) {
            final name = u['display_name'] ?? u['name'] ?? 'User';
            return _buildChannelTile(
              name: name.toString(),
              icon: Icons.person_outline,
              isSelected: false,
              trailing: const Icon(Icons.chat_bubble_outline, size: 14),
              onTap: () {
                _startDirectChat(u);
                onChannelSelected?.call();
              },
            );
          }),
        ],
      ],
    );
  }

  Widget _buildChannelTile({
    required String name,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final bg = isSelected
        ? context.primaryColor.withValues(alpha: 0.12)
        : Colors.transparent;
    final fg = isSelected ? context.primaryColor : context.inkColor;
    final iconColor = isSelected ? context.primaryColor : context.mutedColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(context.radiusControl),
        child: InkWell(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          enableFeedback: false,
          hoverColor: context.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(context.radiusControl),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.bodyStyle.copyWith(
                      fontSize: 13,
                      color: fg,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanel({
    bool isSmallScreen = false,
    VoidCallback? onBack,
    VoidCallback? onClose,
  }) {
    Map<String, dynamic> activeChannel = const {};
    for (final c in _channels) {
      if (c['id']?.toString() == _selectedChannelId) {
        activeChannel = c;
        break;
      }
    }
    final activeRawName = activeChannel['name']?.toString() ?? 'Conversation';
    final activeName = _formatChannelName(activeRawName);
    final activeScope = activeChannel['scope']?.toString() ?? 'public';

    return Column(
      children: [
        // Active Channel Header Bar on Mobile
        if (isSmallScreen)
          Container(
            height: 48,
            padding: const EdgeInsets.only(left: 6, right: 6),
            decoration: BoxDecoration(
              color: context.panelColor,
              border: Border(
                bottom: BorderSide(color: context.subtleBorderColor),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('comm_link_close_button'),
                  icon: const Icon(Icons.close, size: 18),
                  color: context.mutedColor,
                  tooltip: 'Close messages',
                  onPressed: onClose,
                ),
                const SizedBox(width: 2),
                IconButton(
                  key: const ValueKey('comm_link_back_button'),
                  icon: const Icon(Icons.arrow_back, size: 20),
                  color: context.inkColor,
                  tooltip: 'Back to chats',
                  onPressed: onBack,
                ),
                const SizedBox(width: 4),
                Icon(_channelIcon(activeScope),
                    size: 18, color: context.primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activeName,
                    style: context.bodyStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: context.inkColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        // Message stream
        Expanded(
          child: _messagesLoading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet. Start the conversation.',
                        style: context.bodyStyle
                            .copyWith(color: context.mutedColor),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        var rawDisplayName =
                            message['sender_display_name']?.toString() ?? '';
                        final senderHumanId =
                            message['sender_human_id']?.toString() ?? '';
                        final currentHumanId =
                            widget.state?.human['id']?.toString() ?? '';
                        final currentHumanDisplayName =
                            widget.state?.human['display_name']?.toString() ??
                            widget.state?.human['displayName']?.toString() ??
                            widget.state?.human['name']?.toString() ?? '';

                        final isCitizenIdPattern = RegExp(r'^H-\d+$', caseSensitive: false).hasMatch(rawDisplayName);
                        if (rawDisplayName.isEmpty || isCitizenIdPattern) {
                          if (currentHumanId.isNotEmpty && senderHumanId == currentHumanId && currentHumanDisplayName.isNotEmpty) {
                            rawDisplayName = currentHumanDisplayName;
                          } else if (rawDisplayName.isEmpty && currentHumanDisplayName.isNotEmpty) {
                            rawDisplayName = currentHumanDisplayName;
                          }
                        }

                        final isOwn = (currentHumanId.isNotEmpty && senderHumanId == currentHumanId) ||
                            (currentHumanDisplayName.isNotEmpty &&
                                (rawDisplayName == currentHumanDisplayName ||
                                    rawDisplayName.startsWith(currentHumanDisplayName)));

                        final rawHouseName =
                            message['sender_house_name']?.toString() ??
                            message['sender_dynasty_name']?.toString() ??
                            '';
                        final senderFullName = rawDisplayName.isNotEmpty
                            ? (rawHouseName.isNotEmpty &&
                                    !rawDisplayName.contains(rawHouseName)
                                ? '$rawDisplayName of $rawHouseName'
                                : rawDisplayName)
                            : (rawHouseName.isNotEmpty
                                ? 'House of $rawHouseName'
                                : 'Citizen');
                        final body = message['body']?.toString() ?? '';
                        final gameDay = asInt(message['game_day']);
                        final gameMinute = asInt(message['game_minute']);
                        final timeFormatted = (gameDay != null && gameMinute != null)
                            ? formatGameDateTime(gameDay, gameMinute)
                            : (gameDay != null
                                ? 'DAY $gameDay'
                                : null);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Align(
                            alignment: isOwn
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints:
                                  const BoxConstraints(maxWidth: 620),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isOwn
                                    ? context.primaryColor.withValues(alpha: 0.14)
                                    : context.panelColor,
                                borderRadius: BorderRadius.circular(
                                    context.radiusControl),
                                border: Border.all(
                                    color: isOwn
                                        ? context.primaryColor.withValues(alpha: 0.3)
                                        : context.subtleBorderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: isOwn
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: isOwn
                                        ? [
                                            if (timeFormatted != null) ...[
                                              Text(
                                                timeFormatted,
                                                style: context.widgetFooterStyle
                                                    .copyWith(fontSize: 8.5),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            Text(
                                              senderFullName,
                                              style: context.captionStyle.copyWith(
                                                color: context.primaryColor,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ]
                                        : [
                                            Text(
                                              senderFullName,
                                              style: context.captionStyle.copyWith(
                                                color: context.primaryColor,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (timeFormatted != null) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                timeFormatted,
                                                style: context.widgetFooterStyle
                                                    .copyWith(fontSize: 8.5),
                                              ),
                                            ],
                                          ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    body,
                                    style: context.bodyStyle.copyWith(
                                      color: context.inkColor,
                                      fontSize: 13,
                                      height: 1.35,
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

        // Input Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.panelColor,
            border:
                Border(top: BorderSide(color: context.subtleBorderColor)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius:
                          BorderRadius.circular(context.radiusControl),
                      border: Border.all(color: context.subtleBorderColor),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter, control: true):
                              _sendMessage,
                          const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                              _sendMessage,
                        },
                        child: TextField(
                          controller: _messageController,
                          minLines: 1,
                          maxLines: 4,
                          style: context.bodyStyle.copyWith(
                            color: context.inkColor,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 10),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                EarthButton(
                  label: 'SEND',
                  variant: EarthButtonVariant.primary,
                  icon: Icons.send,
                  height: double.infinity,
                  onPressed: _sending ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
