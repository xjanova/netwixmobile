import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netwix/models/content.dart';
import 'package:netwix/models/episode.dart';
import 'package:netwix/models/member.dart';
import 'package:netwix/models/wallet.dart';
import 'package:netwix/services/format.dart';
import 'package:netwix/services/netwix_api.dart';
import 'package:netwix/theme/hex.dart';

void main() {
  group('share links match real web routes', () {
    // The app used to share /t/{slug} and /r/{code} — neither route has ever
    // existed, so every shared link 404'd.
    test('titleUrl uses /title/{slug} (Content binds by slug)', () {
      expect(NetwixApi.titleUrl('purpose-of-reunion'),
          'https://netwix.online/title/purpose-of-reunion');
    });

    test('referralUrl uses /register?ref= (RegisterController redeems it)', () {
      expect(NetwixApi.referralUrl('ABC123'), 'https://netwix.online/register?ref=ABC123');
    });

    test('referralUrl encodes a code with URL-unsafe characters', () {
      // Query-component encoding: space becomes '+', which PHP's parse_str
      // decodes back to a space. The '&' must be escaped so it can't inject a
      // second parameter.
      expect(NetwixApi.referralUrl('a b&c'), 'https://netwix.online/register?ref=a+b%26c');
    });
  });

  group('NetwixSource distinguishes a paywall from a mirroring delay', () {
    test('403 pro_required is locked, not preparing', () {
      final s = NetwixSource.fromJson({'ready': false, 'error': 'pro_required'});
      expect(s.isLocked, isTrue);
      expect(s.isPreparing, isFalse);
      expect(s.isGone, isFalse);
    });

    test('403 vip_required is locked', () {
      final s = NetwixSource.fromJson({'ready': false, 'error': 'vip_required'});
      expect(s.isLocked, isTrue);
      expect(s.isPreparing, isFalse);
    });

    test('404 no_source is gone, not preparing', () {
      final s = NetwixSource.fromJson({'ready': false, 'error': 'no_source'});
      expect(s.isGone, isTrue);
      expect(s.isPreparing, isFalse);
      expect(s.isLocked, isFalse);
    });

    test('202 with no error really is preparing', () {
      final s = NetwixSource.fromJson({'ready': false});
      expect(s.isPreparing, isTrue);
      expect(s.isLocked, isFalse);
    });

    test('a ready source is none of the failure states', () {
      final s = NetwixSource.fromJson({'ready': true, 'kind': 'mp4', 'url': 'https://x/y.mp4'});
      expect(s.ready, isTrue);
      expect(s.isLocked, isFalse);
      expect(s.isPreparing, isFalse);
    });
  });

  group('playback markers', () {
    test('episode carries the effective markers the API resolved', () {
      final e = Episode.fromJson({
        'id': 1,
        'number': 1,
        'intro_end_seconds': 90,
        'outro_seconds': 45,
      });
      expect(e.introEndSeconds, 90);
      expect(e.outroSeconds, 45);
    });

    test('missing markers default to 0 (= unset, not null-crash)', () {
      final e = Episode.fromJson({'id': 1, 'number': 1});
      expect(e.introEndSeconds, 0);
      expect(e.outroSeconds, 0);
    });

    test('content exposes its own marker defaults', () {
      final c = Content.fromJson({
        'id': 5,
        'slug': 's',
        'title': 't',
        'intro_end_seconds': 60,
        'outro_seconds': 30,
      });
      expect(c.introEndSeconds, 60);
      expect(c.outroSeconds, 30);
    });
  });

  group('content access gates', () {
    test('VIP + adult flags parse and drive isGated', () {
      final c = Content.fromJson({
        'id': 1,
        'slug': 's',
        'title': 't',
        'is_vip': true,
        'vip_price_gold': 20,
        'is_adult': true,
        'requires_pro': true,
      });
      expect(c.isVip, isTrue);
      expect(c.vipPriceGold, 20);
      expect(c.isAdult, isTrue);
      expect(c.requiresPro, isTrue);
      expect(c.isGated, isTrue);
    });

    test('an ordinary title is not gated', () {
      final c = Content.fromJson({'id': 1, 'slug': 's', 'title': 't'});
      expect(c.isGated, isFalse);
    });
  });

  group('Comment reads what the server actually sends', () {
    test('avatar_color is picked up (the model used to read a nonexistent "avatar")', () {
      final c = Comment.fromJson({
        'id': 7,
        'author': 'สมชาย',
        'avatar_color': '#b026ff',
        'text': 'ดีมาก',
        'created_at': '2026-07-15T10:00:00+00:00',
      });
      expect(c.avatarColor, '#b026ff');
      expect(c.text, 'ดีมาก');
      expect(c.createdAt, isNotNull);
    });

    test('an unparseable timestamp is null, not epoch 0', () {
      final c = Comment.fromJson({'id': 1, 'author': 'a', 'text': 'x'});
      expect(c.createdAt, isNull);
    });

    test('initial is grapheme-safe for Thai and emoji', () {
      expect(Comment.fromJson({'id': 1, 'author': 'สมชาย', 'text': ''}).initial, 'ส');
      expect(Comment.fromJson({'id': 1, 'author': '👨‍👩‍👧 fam', 'text': ''}).initial, '👨‍👩‍👧');
      expect(Comment.fromJson({'id': 1, 'author': '  ', 'text': ''}).initial, '?');
    });
  });

  group('HexAvatar.parseColor', () {
    test('parses #rrggbb and bare rrggbb', () {
      expect(HexAvatar.parseColor('#b026ff'), const Color(0xFFB026FF));
      expect(HexAvatar.parseColor('b026ff'), const Color(0xFFB026FF));
    });

    test('expands a 3-digit shorthand', () {
      expect(HexAvatar.parseColor('#f0a'), const Color(0xFFFF00AA));
    });

    test('returns null on junk rather than throwing', () {
      expect(HexAvatar.parseColor(null), isNull);
      expect(HexAvatar.parseColor(''), isNull);
      expect(HexAvatar.parseColor('nope'), isNull);
      expect(HexAvatar.parseColor('#12345'), isNull);
    });
  });

  group('gold convert preview', () {
    test('floors to whole gold at the server rate', () {
      const g = GoldState(convertRate: 100, convertFeePct: 0);
      expect(g.previewGoldFor(500), 5);
      expect(g.previewGoldFor(550), 5); // partial gold is not credited
      expect(g.previewGoldFor(99), 0);
    });

    test('applies the fee percentage', () {
      const g = GoldState(convertRate: 100, convertFeePct: 10);
      expect(g.previewGoldFor(1000), 9); // 10 gross - 10%
    });

    test('a zero/negative rate cannot divide by zero', () {
      const g = GoldState(convertRate: 0);
      expect(g.previewGoldFor(1000), 0);
    });
  });

  group('UsdtOrder keeps the exact payable amount', () {
    // The server matches a deposit by its EXACT 6-decimal amount, so the string
    // must survive verbatim — a double round-trip would break matching.
    test('amount_usdt is kept as the server string, not a double', () {
      final o = UsdtOrder.fromJson({
        'reference': 'NX-ABC123',
        'status': 'pending',
        'purpose': 'gold',
        'amount_usdt': '5.000123',
        'wallet': '0xabc',
        'credited_gold': 500,
      });
      expect(o.amountUsdt, '5.000123');
      expect(o.reference, 'NX-ABC123');
      expect(o.creditedGold, 500);
      expect(o.isPending, isTrue);
    });

    test('trailing-zero precision is not lost', () {
      final o = UsdtOrder.fromJson({'reference': 'r', 'amount_usdt': '1.000000'});
      expect(o.amountUsdt, '1.000000');
    });

    test('confirming state needs a tx below the confirmation threshold', () {
      final o = UsdtOrder.fromJson({
        'reference': 'r',
        'status': 'pending',
        'amount_usdt': '1.0',
        'tx_hash': '0xdead',
        'confirmations': 2,
        'min_confirmations': 6,
      });
      expect(o.isConfirming, isTrue);
    });
  });

  group('UsdtConfig.usable guards an unconfigured wallet', () {
    // Prod currently has enabled=false and an empty wallet — the UI must hide the
    // flow rather than show an order with nowhere to send funds.
    test('disabled or address-less is not usable', () {
      expect(const UsdtConfig(enabled: false, wallet: '0xabc').usable, isFalse);
      expect(const UsdtConfig(enabled: true, wallet: '').usable, isFalse);
      expect(const UsdtConfig(enabled: true, wallet: null).usable, isFalse);
    });

    test('enabled with an address is usable', () {
      expect(const UsdtConfig(enabled: true, wallet: '0xabc').usable, isTrue);
    });
  });

  group('Format.ago', () {
    test('buckets by magnitude in Thai and English', () {
      final now = DateTime.now();
      expect(Format.ago(now.subtract(const Duration(seconds: 5))), 'เมื่อสักครู่');
      expect(Format.ago(now.subtract(const Duration(minutes: 5))), '5 นาทีที่แล้ว');
      expect(Format.ago(now.subtract(const Duration(hours: 3))), '3 ชั่วโมงที่แล้ว');
      expect(Format.ago(now.subtract(const Duration(days: 2))), '2 วันที่แล้ว');
      expect(Format.ago(now.subtract(const Duration(minutes: 5)), thai: false), '5m ago');
    });

    test('falls back to an exact date beyond a month', () {
      final old = DateTime(2020, 3, 9);
      expect(Format.ago(old), '09/03/2020');
    });
  });

  test('Format.date is zero-padded dd/mm/yyyy', () {
    expect(Format.date(DateTime(2026, 7, 5)), '05/07/2026');
  });
}
