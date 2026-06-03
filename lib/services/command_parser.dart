/// Parsed ATC instruction — fields will be expanded in Phase 3.
class ParsedCommand {
  const ParsedCommand({
    required this.callsign,
    required this.action,
  });

  final String callsign;
  final String action;
}

/// Parses transcribed ATC text into structured commands.
///
/// Placeholder — logic to be implemented in Phase 3.
class CommandParser {
  CommandParser._();

  static ParsedCommand? parse(String input) {
    throw UnimplementedError('CommandParser.parse — coming in Phase 3');
  }
}
