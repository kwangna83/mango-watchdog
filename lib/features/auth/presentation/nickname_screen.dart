import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/validation/input_validators.dart';
import 'auth_controller.dart';

class NicknameScreen extends ConsumerStatefulWidget {
  const NicknameScreen({super.key});
  @override
  ConsumerState<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends ConsumerState<NicknameScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('접속하지 못했어요. 잠시 후 다시 시도해 주세요.')),
        );
      }
    });
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _MangoMark(),
                    const SizedBox(height: 32),
                    Text(
                      '반가워요!',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('채팅에서 사용할 닉네임을 알려주세요.'),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _controller,
                      autofocus: true,
                      maxLength: 20,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: '닉네임',
                        hintText: '예: 망고',
                        prefixIcon: Icon(Icons.face_rounded),
                      ),
                      validator: InputValidators.nickname,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: auth.isLoading ? null : _submit,
                      icon:
                          auth.isLoading
                              ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.arrow_forward_rounded),
                      label: const Text('채팅 시작하기'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    ref.read(authControllerProvider.notifier).signIn(_controller.text);
  }
}

class _MangoMark extends StatelessWidget {
  const _MangoMark();
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      width: 88,
      height: 88,
      decoration: const BoxDecoration(
        color: AppColors.mango,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.chat_bubble_rounded,
        size: 42,
        color: AppColors.ink,
      ),
    ),
  );
}
