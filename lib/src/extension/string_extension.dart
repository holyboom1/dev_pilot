extension StringExtension on String? {
  bool toBool() {
    switch (this) {
      case 'true':
        return true;
      case 'yes':
        return true;
      case 'no':
        return false;
      case 'false':
        return false;
      default:
        return false;
    }
  }

  String snakeCase() {
    if (this == null) {
      return '';
    }
    final String result = this!
        .replaceAllMapped(RegExp('([A-Z])'), (Match match) => '_${match.group(0)?.toLowerCase()}');
    return result.replaceAll(' ', '_').toLowerCase();
  }

  String toCamelCase() {
    if (this == null) {
      return '';
    }
    return this!
        .replaceAllMapped(RegExp(r'(^|[_\s])(\w)'), (Match match) => match.group(2)!.toUpperCase());
  }

  int toInt() {
    return int.tryParse(this ?? '') ?? 0;
  }
}
