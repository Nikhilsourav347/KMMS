import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain.dart';
import 'repository.dart';

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .21),
    child: Image.asset(
      logoAsset,
      width: size,
      height: size,
      semanticLabel: companyName,
    ),
  );
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(height: 18),
              children[index],
            ],
          ],
        ),
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.detail, this.action});
  final String title;
  final String? detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.headlineMedium),
            if (detail != null) ...[
              const SizedBox(height: 5),
              Text(detail!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
        ?action,
      ],
    );
  }
}

class Notice extends StatelessWidget {
  const Notice(
    this.message, {
    super.key,
    this.icon = Icons.info_outline,
    this.action,
  });
  final String message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 10), action!],
      ],
    ),
  );
}

Widget loadView<T>(
  AsyncValue<T> state,
  Widget Function(T) builder,
  VoidCallback retry,
) {
  if (state.hasError) {
    return Notice(
      friendlyError(state.error!),
      icon: Icons.cloud_off_outlined,
      action: OutlinedButton(onPressed: retry, child: const Text('Retry')),
    );
  }
  if (state.hasValue) return builder(state.requireValue);
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: CircularProgressIndicator(),
    ),
  );
}

class ToneBadge extends StatelessWidget {
  const ToneBadge(this.label, this.color, {super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? .34 : .11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: dark ? Color.lerp(color, Colors.white, .65) : color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class DateField extends StatelessWidget {
  const DateField(
    this.label,
    this.value,
    this.onChanged, {
    super.key,
    this.first,
    this.last,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime>? onChanged;
  final DateTime? first;
  final DateTime? last;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onChanged == null
        ? null
        : () async {
            final low = first ?? DateTime(2000);
            final high = last ?? DateTime(2100, 12, 31);
            var initial = value ?? indiaToday();
            if (initial.isBefore(low)) initial = low;
            if (initial.isAfter(high)) initial = high;
            final date = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: low,
              lastDate: high,
              currentDate: indiaToday(),
              helpText: label,
            );
            if (date != null) onChanged!(date);
          },
    icon: const Icon(Icons.calendar_today_outlined, size: 17),
    label: Text(value == null ? label : '$label · ${prettyDate(value!)}'),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void notify(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class SearchPicker extends StatelessWidget {
  const SearchPicker({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.allowClear = true,
    this.placeholder,
  });
  final String label;
  final Map<String, String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final bool allowClear;
  final String? placeholder;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          icon: const Icon(Icons.search, size: 19),
          label: Text(
            options[value] ?? placeholder ?? label,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: !enabled
              ? null
              : () async {
                  final result = await showDialog<String>(
                    context: context,
                    builder: (context) =>
                        _PickerDialog(title: label, options: options),
                  );
                  if (result != null) onChanged(result);
                },
        ),
      ),
      if (allowClear && value != null)
        IconButton(
          tooltip: 'Clear $label',
          onPressed: enabled ? () => onChanged(null) : null,
          icon: const Icon(Icons.close),
        ),
    ],
  );
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({required this.title, required this.options});
  final String title;
  final Map<String, String> options;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final matching = widget.options.entries
        .where((option) => option.value.toLowerCase().contains(query))
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        height: 335,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matching.isEmpty
                  ? const Center(child: Text('No matching records'))
                  : ListView.builder(
                      itemCount: matching.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(matching[i].value),
                        onTap: () => Navigator.pop(context, matching[i].key),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class SearchableNameField extends StatelessWidget {
  const SearchableNameField({
    super.key,
    required this.label,
    required this.controller,
    required this.names,
    this.enabled = true,
    this.maxLength = 120,
  });
  final String label;
  final TextEditingController controller;
  final List<String> names;
  final bool enabled;
  final int maxLength;

  @override
  Widget build(BuildContext context) => Autocomplete<String>(
    initialValue: controller.value,
    optionsBuilder: (input) {
      final query = input.text.trim().toLowerCase();
      return names.where((name) => name.toLowerCase().contains(query)).take(30);
    },
    onSelected: (value) => controller.text = value,
    fieldViewBuilder: (context, field, focus, submit) => TextField(
      controller: field,
      focusNode: focus,
      enabled: enabled,
      maxLength: maxLength,
      onChanged: (value) => controller.text = value,
      onSubmitted: (_) => submit(),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        suffixIcon: const Icon(Icons.expand_more),
      ),
    ),
  );
}

class IndiaClock extends StatefulWidget {
  const IndiaClock({super.key, required this.builder});
  final Widget Function(BuildContext context, ShiftWindow window) builder;
  @override
  State<IndiaClock> createState() => _IndiaClockState();
}

class _IndiaClockState extends State<IndiaClock> {
  late final Timer timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => setState(() {}));
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, ShiftWindow.at(DateTime.now()));
}
