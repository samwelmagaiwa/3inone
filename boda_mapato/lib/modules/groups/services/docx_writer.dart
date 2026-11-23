import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'group_doc.dart';

/// Writes a [GroupDoc] as a Word file (.docx): a zip of three small XML parts. No Word library is needed; every letter (Swahili too) is kept.
class DocxWriter {
  const DocxWriter._();

  static String _esc(final String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  static String _run(final String text, {final bool bold = false, final int size = 22, final String color = '1A1A1A'}) =>
      '<w:r><w:rPr>${bold ? '<w:b/>' : ''}<w:color w:val="$color"/><w:sz w:val="$size"/></w:rPr><w:t xml:space="preserve">${_esc(text)}</w:t></w:r>';

  static String _para(final String runs, {final int after = 80}) => '<w:p><w:pPr><w:spacing w:before="0" w:after="$after"/></w:pPr>$runs</w:p>';

  static String _cell(final String text, final int width, {final bool bold = false}) =>
      '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/></w:tcPr>${_para(_run(text, bold: bold, size: 18), after: 40)}</w:tc>';

  static String _table(final DocTable t, {final bool wide = false}) {
    final int cols = t.head.length;
    final int width = (wide ? 14000 : 9000) ~/ cols;
    String row(final List<String> cells, {final bool bold = false}) => '<w:tr>${cells.map((final String c) => _cell(c, width, bold: bold)).join()}</w:tr>';
    return '<w:tbl><w:tblPr><w:tblW w:w="${wide ? 14000 : 9000}" w:type="dxa"/><w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="CCCCCC"/><w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/><w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>'
        '</w:tblBorders></w:tblPr>${row(t.head, bold: true)}${t.rows.map(row).join()}</w:tbl>${_para('')}';
  }

  static String _body(final GroupDoc d) {
    final StringBuffer b = StringBuffer()
      ..write(_para(_run(d.group, bold: true, size: 36), after: 20))
      ..write(_para(_run(d.title, size: 24, color: '666666'), after: 160));
    for (final DocBlock x in d.blocks) {
      switch (x) {
        case DocHeading():
          b.write(_para(_run(x.text, bold: true, size: 26), after: 60));
        case DocRows():
          for (final DocRow r in x.rows) {
            b.write(_para('${_run('${r.label}:  ', size: 20, color: '666666')}${_run(r.value, bold: r.bold)}', after: 40));
          }
        case DocTable():
          b.write(_table(x, wide: d.wide));
        case DocNote():
          b.write(_para(_run(x.text, size: 16, color: '666666')));
        case DocQr():
          b.write(_para('${_run('${x.caption}: ', size: 16, color: '666666')}${_run(x.data, size: 16, color: '666666')}'));
      }
    }
    return b.toString();
  }

  /// The bytes of the .docx.
  static Uint8List build(final GroupDoc d) {
    const String xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    final String doc = '$xml<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${_body(d)}'
        '<w:sectPr><w:pgSz w:w="${d.small ? 8391 : (d.wide ? 16838 : 11906)}" w:h="${d.small ? 11906 : (d.wide ? 11906 : 16838)}"${d.wide ? ' w:orient="landscape"' : ''}/><w:pgMar w:top="1000" w:right="1200" w:bottom="1000" w:left="1200" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';
    const String types = '$xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
    const String rels = '$xml<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
    final Archive zip = Archive();
    void add(final String name, final String content) {
      final List<int> bytes = utf8.encode(content);
      zip.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml', types);
    add('_rels/.rels', rels);
    add('word/document.xml', doc);
    return Uint8List.fromList(ZipEncoder().encode(zip)!);
  }
}
