part of '../main.dart';

class _Spb3dArrowButton extends StatelessWidget {
  const _Spb3dArrowButton({
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) {
      return const SizedBox(width: 38, height: 34);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(3),
        child: Ink(
          width: 38,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xff676767)),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xfff4f4f4), Color(0xff8d8d8d)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.white,
                offset: Offset(-1, -1),
                blurRadius: 0.5,
              ),
              BoxShadow(
                color: Color(0x66000000),
                offset: Offset(1, 1),
                blurRadius: 1,
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 30,
            color: const Color(0xff303030),
            shadows: const [
              Shadow(color: Colors.white70, offset: Offset(0, -1)),
              Shadow(color: Color(0x66000000), offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }
}

class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({required this.password, super.key});

  final String password;

  @override
  Widget build(BuildContext context) {
    final score = passwordStrengthScore(password);
    const colors = <Color>[
      Color(0xffb71c1c),
      Color(0xffd32f2f),
      Color(0xfff57c00),
      Color(0xfffbc02d),
      Color(0xff7cb342),
      Color(0xff2e7d32),
    ];
    const labels = <String>[
      'не задан',
      'очень слабый',
      'слабый',
      'средний',
      'надежный',
      'очень надежный',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 2,
          children: [
            const Text('Надежность пароля'),
            Text(labels[score]),
          ],
        ),
        const SizedBox(height: 4),
        ClipRect(
          child: LinearProgressIndicator(
            minHeight: 8,
            value: score == 0 ? 0 : score / 5,
            backgroundColor: const Color(0xffc8c8c8),
            valueColor: AlwaysStoppedAnimation<Color>(colors[score]),
          ),
        ),
      ],
    );
  }
}

class PasswordField extends StatelessWidget {
  const PasswordField({
    required this.controller,
    required this.label,
    required this.visible,
    required this.onToggle,
    this.onChanged,
    this.onSubmitted,
    this.compact = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool visible;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textCapitalization: TextCapitalization.none,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: compact,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : null,
        suffixIconConstraints: compact
            ? const BoxConstraints.tightFor(width: 40, height: 40)
            : null,
        suffixIcon: IconButton(
          padding: compact ? EdgeInsets.zero : null,
          tooltip: visible ? 'Скрыть' : 'Показать',
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
      ),
    );
    return compact ? SizedBox(height: 42, child: field) : field;
  }
}

class NavigationButton extends StatelessWidget {
  const NavigationButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor:
              selected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
      ),
    );
  }
}

class CountBadgeButton extends StatelessWidget {
  const CountBadgeButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
        if (count > 0)
          Positioned(
            right: -5,
            top: -7,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onError,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
