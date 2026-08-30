String defaultIconForTemplateName(
  String name,
  Iterable<String> fieldLabels,
) {
  final text = ([name, ...fieldLabels]).join(' ').toLowerCase();
  if (text.contains('банк') ||
      text.contains('bank') ||
      text.contains('счет') ||
      text.contains('account')) {
    return 'bank';
  }
  if (text.contains('карта') || text.contains('card') || text.contains('cvv')) {
    return 'card';
  }
  if (text.contains('wi-fi') ||
      text.contains('wifi') ||
      text.contains('ssid')) {
    return 'wifi';
  }
  if (text.contains('почт') ||
      text.contains('mail') ||
      text.contains('email')) {
    return 'mail';
  }
  if (text.contains('паспорт') ||
      text.contains('документ') ||
      text.contains('удостовер') ||
      text.contains('document') ||
      text.contains('identity')) {
    return 'id';
  }
  if (text.contains('сервер') ||
      text.contains('server') ||
      text.contains('ssh') ||
      text.contains('host')) {
    return 'server';
  }
  if (text.contains('лиценз') ||
      text.contains('license') ||
      text.contains('ключ продукта')) {
    return 'license';
  }
  if (text.contains('замет') ||
      text.contains('note') ||
      text.contains('memo')) {
    return 'note';
  }
  if (text.contains('телефон') || text.contains('phone')) return 'phone';
  if (text.contains('сайт') ||
      text.contains('url') ||
      text.contains('web') ||
      text.contains('internet')) {
    return 'globe';
  }
  if (text.contains('облак') || text.contains('cloud')) return 'cloud';
  if (text.contains('база') || text.contains('database')) return 'database';
  if (text.contains('крипт') ||
      text.contains('bitcoin') ||
      text.contains('crypto')) {
    return 'crypto';
  }
  return 'key';
}
