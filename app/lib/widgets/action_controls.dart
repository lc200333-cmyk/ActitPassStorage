part of '../main.dart';

class SpbGradientActionButton extends StatelessWidget {
  const SpbGradientActionButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final List<Color> colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Center(
        child: Tooltip(
          message: tooltip,
          child: Opacity(
            opacity: onTap == null ? 0.55 : 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Ink(
                  width: 38,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: colors,
                    ),
                    border: Border.all(color: const Color(0xff56636c)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ColorPicker extends StatelessWidget {
  const ColorPicker({
    required this.value,
    required this.onChanged,
    this.label = 'Цвет карточки',
    this.keyPrefix = 'cardColor',
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final color in templateColorPalette)
              Tooltip(
                message: color.label,
                child: InkWell(
                  onTap: () => onChanged(color.id),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    key: ValueKey('$keyPrefix-${color.id}'),
                    width: 30,
                    height: 27,
                    decoration: BoxDecoration(
                      color: color.bg,
                      border: Border.all(
                        color: color.id == value
                            ? const Color(0xff253d4c)
                            : const Color(0xff8b969d),
                        width: color.id == value ? 2.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1f000000),
                          offset: Offset(1, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: color.id == value
                        ? const Icon(Icons.check, size: 17)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
