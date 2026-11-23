/// One document of the Groups (Vikundi) service described once, so the same content becomes a PDF, a picture (a one-page PDF) or a Word
/// file (.docx). Reports, statements, loan statements and receipts are all built as a [GroupDoc].
library;

import 'package:flutter/foundation.dart';

/// A piece of a document.
@immutable
sealed class DocBlock {
  const DocBlock();
}

/// A bold heading above a part.
class DocHeading extends DocBlock {
  const DocHeading(this.text);
  final String text;
}

/// Label / value lines.
class DocRows extends DocBlock {
  const DocRows(this.rows);
  final List<DocRow> rows;
}

class DocRow {
  const DocRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;
}

/// A table with a header line.
class DocTable extends DocBlock {
  const DocTable(this.head, this.rows, {this.widths});
  final List<String> head;
  final List<List<String>> rows;

  /// Fixed widths (points) for some columns, by column index; the rest share what is left.
  final Map<int, double>? widths;
}

/// A small grey line of text.
class DocNote extends DocBlock {
  const DocNote(this.text);
  final String text;
}

/// A QR code that holds [data] (a Word file shows the link as text instead).
class DocQr extends DocBlock {
  const DocQr(this.data, this.caption);
  final String data;
  final String caption;
}

class GroupDoc {
  const GroupDoc({required this.group, required this.title, required this.blocks, this.small = false, this.wide = false, this.fileName = 'document'});

  final String group;
  final String title;
  final List<DocBlock> blocks;

  /// A short receipt-sized page (A5) rather than a full A4 page.
  final bool small;

  /// A landscape A4 page, for wide tables such as the member register.
  final bool wide;

  /// The file name without its ending.
  final String fileName;
}
