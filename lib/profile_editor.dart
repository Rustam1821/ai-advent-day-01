import 'package:flutter/material.dart';

import 'agent_profile.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.profile});
  final AgentProfile profile;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _fields = [
    TextEditingController(text: widget.profile.name),
    TextEditingController(text: widget.profile.userName),
    TextEditingController(text: widget.profile.style),
    TextEditingController(text: widget.profile.format),
    TextEditingController(text: widget.profile.constraints),
  ];
  static const _labels = [
    'Название', 'Обращение', 'Стиль ответа', 'Формат ответа',
    'Ограничения / дополнительные правила',
  ];

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Редактировать профиль'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _fields[i],
                    minLines: 1,
                    maxLines: i < 2 ? 1 : 4,
                    decoration: InputDecoration(labelText: _labels[i]),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Заполните поле.' : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, AgentProfile(
            id: widget.profile.id,
            name: _fields[0].text.trim(),
            userName: _fields[1].text.trim(),
            style: _fields[2].text.trim(),
            format: _fields[3].text.trim(),
            constraints: _fields[4].text.trim(),
          ));
        },
        child: const Text('Сохранить'),
      ),
    ],
  );
}
