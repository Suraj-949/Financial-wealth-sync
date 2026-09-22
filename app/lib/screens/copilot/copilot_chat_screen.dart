import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';
import '../../services/mock_data.dart';

class CopilotChatScreen extends StatefulWidget {
  const CopilotChatScreen({super.key});

  @override
  State<CopilotChatScreen> createState() => _CopilotChatScreenState();
}

class _CopilotChatScreenState extends State<CopilotChatScreen> {
  final repo = getRepository();
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  final List<CopilotMessage> _messages = [];
  bool _typing = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(CopilotMessage(text: text, fromUser: true, time: DateTime.now()));
      _typing = true;
    });
    _controller.clear();
    _jumpToBottom();

    try {
      final reply = await repo.copilotAsk(text);
      if (!mounted) return;
      setState(() {
        _messages.add(CopilotMessage(text: reply.text, fromUser: false, time: DateTime.now()));
        if (reply.bullets.isNotEmpty) {
          _messages.add(CopilotMessage(
            text: reply.bullets.join('\n• '),
            fromUser: false,
            time: DateTime.now(),
          ));
        }
        _typing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _typing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Copilot is unavailable right now.')));
    }
    _jumpToBottom();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AI Financial Copilot'),
            const SizedBox(width: 8),
            TagBadge.beta(),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 14),
            child: Icon(Icons.info_outline, size: 20, color: AppColors.textMuted),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _groundingBanner(),
            Expanded(
              child: _messages.isEmpty ? _welcome() : _chatList(),
            ),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _groundingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      color: AppColors.ai.withValues(alpha: .10),
      child: const Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 14, color: AppColors.ai),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Grounded answers: your data + ML + explanations + recommendations.',
              style: TextStyle(color: AppColors.ai, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcome() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      children: [
        _bubble(
          text: 'Hi Suraj! 👋 Ask me anything about your finances.',
          fromUser: false,
        ),
        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Suggested questions',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final q in MockData.copilotSuggested)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(q, style: const TextStyle(fontSize: 12.5)),
                    onPressed: () => _send(q),
                    backgroundColor: AppColors.surfaceAlt,
                    side: const BorderSide(color: AppColors.line),
                    labelStyle: const TextStyle(color: AppColors.textPrimary),
                    avatar: const Icon(Icons.auto_awesome, size: 14, color: AppColors.ai),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chatList() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      itemCount: _messages.length + (_typing ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) {
          return _bubble(text: 'Thinking…', fromUser: false, typing: true);
        }
        final m = _messages[i];
        return _bubble(text: m.text, fromUser: m.fromUser);
      },
    );
  }

  Widget _bubble({required String text, required bool fromUser, bool typing = false}) {
    final lines = text.split('\n');
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: fromUser ? AppColors.accent : AppColors.surfaceAlt,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(fromUser ? 14 : 4),
            bottomRight: Radius.circular(fromUser ? 4 : 14),
          ),
        ),
        child: typing
            ? Text(text,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: fromUser ? Colors.white : AppColors.textPrimary,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (lines.length == 1 && text.contains('•'))
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('• grounded · ML · XAI · recommendations',
                          style: TextStyle(fontSize: 10.5, color: AppColors.ai)),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      color: AppColors.surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ask a question…',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            onPressed: () => _send(_controller.text),
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Send',
            style: IconButton.styleFrom(backgroundColor: AppColors.accent),
          ),
        ],
      ),
    );
  }
}