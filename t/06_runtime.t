#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Proto::PL::Runtime;

# Test wire format encoding/decoding functions
subtest 'Varint encoding/decoding' => sub {

  # Test small values
  my $encoded = Proto::PL::Runtime::_encode_varint(0);
  is($encoded, "\x00", 'Varint 0 encoded correctly');

  my ($decoded, $consumed) = Proto::PL::Runtime::_decode_varint($encoded, 0);
  is($decoded,  0, 'Varint 0 decoded correctly');
  is($consumed, 1, 'Varint 0 consumed 1 byte');

  # Test larger values
  $encoded = Proto::PL::Runtime::_encode_varint(127);
  is($encoded, "\x7F", 'Varint 127 encoded correctly');

  ($decoded, $consumed) = Proto::PL::Runtime::_decode_varint($encoded, 0);
  is($decoded,  127, 'Varint 127 decoded correctly');
  is($consumed, 1,   'Varint 127 consumed 1 byte');

  # Test multi-byte varint
  $encoded = Proto::PL::Runtime::_encode_varint(128);
  is($encoded, "\x80\x01", 'Varint 128 encoded correctly');

  ($decoded, $consumed) = Proto::PL::Runtime::_decode_varint($encoded, 0);
  is($decoded,  128, 'Varint 128 decoded correctly');
  is($consumed, 2,   'Varint 128 consumed 2 bytes');

  # Test large value
  $encoded = Proto::PL::Runtime::_encode_varint(16384);
  ($decoded, $consumed) = Proto::PL::Runtime::_decode_varint($encoded, 0);
  is($decoded, 16384, 'Large varint round-trip works');

  # Test very large value
  $encoded = Proto::PL::Runtime::_encode_varint(2**31 - 1);
  ($decoded, $consumed) = Proto::PL::Runtime::_decode_varint($encoded, 0);
  is($decoded, 2**31 - 1, 'Very large varint round-trip works');
};

# Test tag encoding
subtest 'Tag encoding' => sub {

  # Field 1, wire type 0 (varint)
  my $tag = Proto::PL::Runtime::_encode_tag(1, 0);
  is($tag, "\x08", 'Tag (1,0) encoded correctly');

  # Field 1, wire type 2 (length-delimited)
  $tag = Proto::PL::Runtime::_encode_tag(1, 2);
  is($tag, "\x0A", 'Tag (1,2) encoded correctly');

  # Field 15, wire type 0
  $tag = Proto::PL::Runtime::_encode_tag(15, 0);
  is($tag, "\x78", 'Tag (15,0) encoded correctly');

  # Field 16, wire type 0 (requires multi-byte varint)
  $tag = Proto::PL::Runtime::_encode_tag(16, 0);
  is($tag, "\x80\x01", 'Tag (16,0) encoded correctly');
};

# Test string encoding/decoding
subtest 'String encoding/decoding' => sub {

  # Test empty string
  my $encoded = Proto::PL::Runtime::_encode_string('');
  is($encoded, "\x00", 'Empty string encoded correctly');

  my $decoded = Proto::PL::Runtime::_decode_string('');
  is($decoded, '', 'Empty string decoded correctly');

  # Test simple string
  $encoded = Proto::PL::Runtime::_encode_string('hello');
  is($encoded, "\x05hello", 'Simple string encoded correctly');

  $decoded = Proto::PL::Runtime::_decode_string('hello');
  is($decoded, 'hello', 'Simple string decoded correctly');

  # Test UTF-8 string
  my $utf8_str = "Hello 世界";
  $encoded = Proto::PL::Runtime::_encode_string($utf8_str);

  # Extract the string part (skip length prefix)
  my $string_part = substr($encoded, 1);
  $decoded = Proto::PL::Runtime::_decode_string($string_part);
  is($decoded, $utf8_str, 'UTF-8 string round-trip works');

  # Test undef string
  $encoded = Proto::PL::Runtime::_encode_string(undef);
  is($encoded, '', 'Undef string encoded as empty');
};

# Test ZigZag encoding/decoding
subtest 'ZigZag encoding/decoding' => sub {

  # Test positive numbers
  my $encoded = Proto::PL::Runtime::_encode_zigzag32(0);
  is($encoded, 0, 'ZigZag32 0 encoded correctly');

  my $decoded = Proto::PL::Runtime::_decode_zigzag32($encoded);
  is($decoded, 0, 'ZigZag32 0 decoded correctly');

  $encoded = Proto::PL::Runtime::_encode_zigzag32(1);
  is($encoded, 2, 'ZigZag32 1 encoded correctly');

  $decoded = Proto::PL::Runtime::_decode_zigzag32($encoded);
  is($decoded, 1, 'ZigZag32 1 decoded correctly');

  # Test negative numbers
  $encoded = Proto::PL::Runtime::_encode_zigzag32(-1);
  is($encoded, 1, 'ZigZag32 -1 encoded correctly');

  $decoded = Proto::PL::Runtime::_decode_zigzag32($encoded);
  is($decoded, -1, 'ZigZag32 -1 decoded correctly');

  $encoded = Proto::PL::Runtime::_encode_zigzag32(-2);
  is($encoded, 3, 'ZigZag32 -2 encoded correctly');

  $decoded = Proto::PL::Runtime::_decode_zigzag32($encoded);
  is($decoded, -2, 'ZigZag32 -2 decoded correctly');

  # Test 64-bit ZigZag
  $encoded = Proto::PL::Runtime::_encode_zigzag64(-1);
  $decoded = Proto::PL::Runtime::_decode_zigzag64($encoded);
  is($decoded, -1, 'ZigZag64 -1 round-trip works');
};

# Test fixed-width encoding/decoding
subtest 'Fixed-width encoding/decoding' => sub {

  # Test fixed32
  my $encoded = Proto::PL::Runtime::_encode_fixed32(0x12345678);
  is(length($encoded), 4, 'Fixed32 produces 4 bytes');

  my $decoded = Proto::PL::Runtime::_decode_fixed32($encoded);
  is($decoded, 0x12345678, 'Fixed32 round-trip works');

  # Test fixed64
  $encoded = Proto::PL::Runtime::_encode_fixed64(0x123456789ABCDEF0);
  is(length($encoded), 8, 'Fixed64 produces 8 bytes');

  $decoded = Proto::PL::Runtime::_decode_fixed64($encoded);
  is($decoded, 0x123456789ABCDEF0, 'Fixed64 round-trip works');

  # Test signed fixed
  $encoded = Proto::PL::Runtime::_encode_sfixed32(-1);
  $decoded = Proto::PL::Runtime::_decode_sfixed32($encoded);
  is($decoded, -1, 'Signed fixed32 round-trip works');

  $encoded = Proto::PL::Runtime::_encode_sfixed64(-1);
  $decoded = Proto::PL::Runtime::_decode_sfixed64($encoded);
  is($decoded, -1, 'Signed fixed64 round-trip works');
};

# Test float/double encoding/decoding
subtest 'Float/double encoding/decoding' => sub {

  # Test float
  my $encoded = Proto::PL::Runtime::_encode_float(3.14159);
  is(length($encoded), 4, 'Float produces 4 bytes');

  my $decoded = Proto::PL::Runtime::_decode_float($encoded);
  ok(abs($decoded - 3.14159) < 0.0001, 'Float round-trip approximately correct');

  # Test double
  $encoded = Proto::PL::Runtime::_encode_double(3.141592653589793);
  is(length($encoded), 8, 'Double produces 8 bytes');

  $decoded = Proto::PL::Runtime::_decode_double($encoded);
  ok(abs($decoded - 3.141592653589793) < 0.000000000000001, 'Double round-trip approximately correct');

  # Test special values
  $encoded = Proto::PL::Runtime::_encode_float(0.0);
  $decoded = Proto::PL::Runtime::_decode_float($encoded);
  is($decoded, 0.0, 'Float zero round-trip works');
};

# Test Message base class
# subtest 'Message base class' => sub {
#     # Create a simple test message class
#     {
#         package TestMessage;
#         use Proto::PL::Runtime;
#         use parent 'Proto::PL::Runtime::Message';

#         sub test_field {
#             my ($self, $value) = @_;
#             if (@_ > 1) {
#                 $self->{test_field} = $value;
#                 return $self;
#             }
#             return $self->{test_field};
#         }

#         sub _encode_fields {
#             my ($self) = @_;
#             my $buffer = '';
#             if (defined $self->{test_field}) {
#                 $buffer .= Proto::PL::Runtime::_encode_tag(1, 2);
#                 $buffer .= Proto::PL::Runtime::_encode_string($self->{test_field});
#             }
#             return $buffer;
#         }

#         sub _decode_field {
#             my ($self, $field_num, $wire_type, $value) = @_;
#             if ($field_num == 1 && $wire_type == 2) {
#                 $self->{test_field} = Proto::PL::Runtime::_decode_string($value);
#                 return 1;
#             }
#             return 0;
#         }

#         sub _fields_to_hash {
#             my ($self, $hash) = @_;
#             $hash->{test_field} = $self->{test_field} if defined $self->{test_field};
#         }
#     }

#     # Test basic construction
#     my $msg = TestMessage->new();
#     isa_ok($msg, 'TestMessage');
#     isa_ok($msg, 'Proto::PL::Runtime::Message');

#     # Test field access
#     is($msg->test_field('hello'), $msg, 'Setter returns self');
#     is($msg->test_field(), 'hello', 'Getter works');

#     # Test encoding/decoding
#     my $encoded = $msg->encode();
#     ok(length($encoded) > 0, 'Message encodes to non-empty data');

#     my $decoded = TestMessage->decode($encoded);
#     isa_ok($decoded, 'TestMessage');
#     is($decoded->test_field(), 'hello', 'Field survives encode/decode');

#     # Test constructor with args
#     my $msg2 = TestMessage->new(test_field => 'constructor');
#     is($msg2->test_field(), 'constructor', 'Constructor with args works');

#     # Test invalid constructor arg
#     eval {
#         TestMessage->new(invalid_field => 'fail');
#     };
#     ok($@, 'Constructor rejects invalid fields');
#     like($@, qr/Unknown field/, 'Error message is appropriate');

#     # Test hash conversion
#     my $hash = $msg->to_hash();
#     is(ref $hash, 'HASH', 'to_hash returns hash ref');
#     is($hash->{test_field}, 'hello', 'Hash contains field');

#     my $from_hash = TestMessage->from_hash($hash);
#     isa_ok($from_hash, 'TestMessage');
#     is($from_hash->test_field(), 'hello', 'from_hash works');
# };

# Test string camelization/decamelization
subtest 'String camelization' => sub {
  is(Proto::PL::Runtime::Message::_camelize('test_field'),      'testField',     'Simple camelization');
  is(Proto::PL::Runtime::Message::_camelize('long_field_name'), 'longFieldName', 'Multi-word camelization');
  is(Proto::PL::Runtime::Message::_camelize('field'),           'field',         'Single word unchanged');
  is(Proto::PL::Runtime::Message::_camelize(''),                '',              'Empty string unchanged');

  is(Proto::PL::Runtime::Message::_decamelize('testField'),     'test_field',      'Simple decamelization');
  is(Proto::PL::Runtime::Message::_decamelize('longFieldName'), 'long_field_name', 'Multi-word decamelization');
  is(Proto::PL::Runtime::Message::_decamelize('field'),         'field',           'Single word unchanged');
  is(Proto::PL::Runtime::Message::_decamelize(''),              '',                'Empty string unchanged');
};

# Test error conditions
subtest 'Error conditions' => sub {

  # Test truncated varint
  eval {
    Proto::PL::Runtime::_decode_varint("\x80", 0);    # Incomplete varint
  };
  ok($@, 'Truncated varint throws error');
  like($@, qr/Truncated varint/, 'Error message is appropriate');

  # Test varint too long
  eval {
    my $long_varint = "\x80" x 10 . "\x01";           # 10 continuation bytes
    Proto::PL::Runtime::_decode_varint($long_varint, 0);
  };
  ok($@, 'Overly long varint throws error');
  like($@, qr/Varint too long/, 'Error message is appropriate');

  # Test invalid UTF-8 in string decode
  eval {
    Proto::PL::Runtime::_decode_string("\x{FFFF_FFFF}");    # Invalid UTF-8
  };
  ok($@, 'Invalid UTF-8 throws error');
  like($@, qr/Invalid UTF-8/, 'Error message is appropriate');
};

done_testing();
