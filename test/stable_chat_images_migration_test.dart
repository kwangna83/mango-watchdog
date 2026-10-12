import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql =
      File(
        'supabase/migrations/202609290001_stable_chat_images.sql',
      ).readAsStringSync();

  test('migration stores optional positive image dimensions', () {
    expect(sql, contains('add column width integer'));
    expect(sql, contains('add column height integer'));
    expect(sql, contains('p_width integer default null'));
    expect(sql, contains('p_height integer default null'));
  });

  test('message queries return stable attachment cache fields', () {
    expect(sql, contains('attachment_id uuid'));
    expect(sql, contains('attachment_width integer'));
    expect(sql, contains('attachment_height integer'));
    expect(RegExp(r'a\.id, a\.storage_bucket').allMatches(sql), hasLength(2));
  });
}
