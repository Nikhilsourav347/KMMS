import 'package:intl/intl.dart';

const companyName = 'Unique Knitting Mills';
const logoAsset = 'assets/images/company_logo.jpg';
const dias = [26, 28, 30, 32, 34];
const designs = [
  'Single Jersey',
  'Loop Knit',
  'Airtex',
  '4-Track Design',
  'Single Rib',
  'Lycra Rib',
  'Derby Rib',
  'Lycra Derby',
];
typedef RowData = Map<String, dynamic>;

enum StaffRole {
  admin('Admin'),
  manager('Manager');

  const StaffRole(this.label);
  final String label;
}

enum Shift {
  morning('Day'),
  night('Night');

  const Shift(this.label);
  final String label;
}

enum Module {
  machines('Machine Running Status'),
  schedule('Machine Schedule'),
  jobs('Job Entry'),
  production('Production Entry'),
  reports('Reports'),
  profile('Profile');

  const Module(this.label);
  final String label;

  bool availableTo(StaffRole role) =>
      role == StaffRole.manager || (this != jobs && this != production);

  String titleFor(StaffRole role) => label;
}

class Staff {
  const Staff(this.name, this.role);
  final String name;
  final StaffRole role;

  factory Staff.fromRow(RowData row) =>
      Staff(row['full_name'] as String, StaffRole.values.byName(row['role']));
}

// Asia/Kolkata currently observes UTC+05:30 year-round.
DateTime indiaTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 5, minutes: 30));

DateTime plainDate(DateTime time) => DateTime(time.year, time.month, time.day);
DateTime indiaToday() => plainDate(indiaTime(DateTime.now()));
String isoDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
String prettyDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);
String dbDateLabel(Object? date) =>
    date == null ? '—' : prettyDate(DateTime.parse('$date'));
String dbTimeLabel(Object? time) => time == null
    ? '—'
    : '${DateFormat('dd MMM yyyy, h:mm a').format(indiaTime(DateTime.parse('$time')))} IST';

class ShiftWindow {
  const ShiftWindow(this.date, this.shift);
  final DateTime date;
  final Shift shift;

  factory ShiftWindow.at(DateTime instant) {
    final local = indiaTime(instant);
    final minutes = local.hour * 60 + local.minute;
    final day = plainDate(local);
    if (minutes < 510) {
      return ShiftWindow(
        DateTime(day.year, day.month, day.day - 1),
        Shift.night,
      );
    }
    return ShiftWindow(day, minutes < 1230 ? Shift.morning : Shift.night);
  }
}

// Integer grams preserve exact three-decimal kilogram calculations.
int? parseGrams(Object? value) {
  final text = value?.toString().trim() ?? '';
  final parts = RegExp(r'^(-?)(\d{1,12})(?:\.(\d{1,3}))?$').firstMatch(text);
  if (parts == null) return null;
  final grams =
      int.parse(parts[2]!) * 1000 +
      int.parse((parts[3] ?? '').padRight(3, '0'));
  return parts[1] == '-' ? -grams : grams;
}

int grams(Object? value) => parseGrams(value) ?? 0;

String kg(int grams) {
  final absolute = grams.abs();
  final integer = absolute ~/ 1000;
  final fraction = (absolute % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${grams.isNegative ? '-' : ''}$integer${fraction.isEmpty ? '' : '.$fraction'}';
}

String percent(int produced, int ordered) =>
    ordered == 0 ? '0%' : '${(produced * 100 / ordered).toStringAsFixed(1)}%';

String cellText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? '—' : text;
}

List<RowData> rows(Object? data) => (data as List? ?? const []).cast<RowData>();
RowData? related(RowData row, String key) => row[key] as RowData?;
