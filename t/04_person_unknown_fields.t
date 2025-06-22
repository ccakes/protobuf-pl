#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use Example::Person;
use Example::Person::PhoneNumber;
use Example::Person::PhoneType;

# Test unknown field preservation during round-trip encoding/decoding
subtest 'Unknown field preservation' => sub {

  # Create a person with known fields
  my $person = Example::Person->new(
    name     => 'Unknown Field Person',
    id       => 12345,
    is_admin => 1
  );

  # Get the initial encoded data
  my $encoded = $person->encode();

  # Manually inject unknown fields into the encoded data
  # We'll add some unknown fields with different wire types

  # Unknown field 100 (varint) = 42
  my $unknown_varint = _encode_tag(100, 0) . _encode_varint(42);

  # Unknown field 101 (string) = "unknown string"
  my $unknown_string = _encode_tag(101, 2) . _encode_string("unknown string");

  # Unknown field 102 (fixed32) = 0x12345678
  my $unknown_fixed32 = _encode_tag(102, 5) . pack('L<', 0x12345678);

  # Unknown field 103 (fixed64) = use a smaller portable number
  my $unknown_fixed64 = _encode_tag(103, 1) . pack('Q<', 0x123456789ABCD);

  # Insert unknown fields at the end
  my $encoded_with_unknown = $encoded . $unknown_varint . $unknown_string . $unknown_fixed32 . $unknown_fixed64;

  # Decode the message with unknown fields
  my $decoded = Example::Person->decode($encoded_with_unknown);
  isa_ok($decoded, 'Example::Person');

  # Verify known fields are preserved
  is($decoded->name(),             'Unknown Field Person', 'Known field preserved with unknown fields');
  is($decoded->id(),               12345,                  'Known field preserved with unknown fields');
  is($decoded->is_admin(),         1,                      'Known field preserved with unknown fields');
  is($decoded->which_permission(), 'is_admin',             'Oneof preserved with unknown fields');

  # Verify unknown fields are stored
  ok(exists $decoded->{_unknown},              'Unknown fields hash exists');
  ok(scalar(keys %{$decoded->{_unknown}}) > 0, 'Unknown fields were preserved');

  # Re-encode the message - unknown fields should be included
  my $reencoded = $decoded->encode();

  # Decode again to verify round-trip preservation
  my $redecoded = Example::Person->decode($reencoded);

  # Verify known fields still work
  is($redecoded->name(),     'Unknown Field Person', 'Known fields preserved after round-trip');
  is($redecoded->id(),       12345,                  'Known fields preserved after round-trip');
  is($redecoded->is_admin(), 1,                      'Known fields preserved after round-trip');

  # The re-encoded message should be the same length or longer than the original with unknowns
  ok(length($reencoded) >= length($encoded_with_unknown), 'Re-encoded message preserves unknown field data');

  # Verify the unknown fields are still there after round-trip
  ok(exists $redecoded->{_unknown},              'Unknown fields preserved after round-trip');
  ok(scalar(keys %{$redecoded->{_unknown}}) > 0, 'Unknown fields still present after round-trip');
};

# Test unknown fields with complex message
subtest 'Unknown fields with complex message' => sub {

  # Create a complex person
  my $phone1 = Example::Person::PhoneNumber->new(
    number => '555-1111',
    type   => Example::Person::PhoneType::HOME
  );

  my $phone2 = Example::Person::PhoneNumber->new(
    number => '555-2222',
    type   => Example::Person::PhoneType::WORK
  );

  my $person = Example::Person->new(
    name       => 'Complex Unknown Person',
    id         => 98765,
    email      => 'complex@example.com',
    phones     => [ $phone1, $phone2 ],
    attributes => {
      'department' => 'Research',
      'clearance'  => 'Top Secret',
      'project'    => 'Unknown Fields Test'
    },
    permissions => [ 'read', 'write', 'admin', 'unknown_test' ]
  );

  my $encoded = $person->encode();

  # Add multiple unknown fields scattered throughout
  my $unknown_fields = '';
  $unknown_fields .= _encode_tag(50,  0) . _encode_varint(100);                         # Unknown varint
  $unknown_fields .= _encode_tag(51,  2) . _encode_string("first unknown");             # Unknown string
  $unknown_fields .= _encode_tag(52,  0) . _encode_varint(200);                         # Another unknown varint
  $unknown_fields .= _encode_tag(53,  2) . _encode_string("second unknown");            # Another unknown string
  $unknown_fields .= _encode_tag(150, 2) . _encode_bytes(pack('C*', 1, 2, 3, 4, 5));    # Unknown bytes

  my $encoded_with_unknown = $encoded . $unknown_fields;

  # Decode
  my $decoded = Example::Person->decode($encoded_with_unknown);

  # Verify all known fields
  is($decoded->name(),                       'Complex Unknown Person', 'Complex name preserved');
  is($decoded->id(),                         98765,                    'Complex id preserved');
  is($decoded->email(),                      'complex@example.com',    'Complex email preserved');
  is(scalar(@{$decoded->phones()}),          2,                        'Complex phones count preserved');
  is($decoded->phones()->[0]->number(),      '555-1111',               'Complex phone 1 preserved');
  is($decoded->phones()->[1]->number(),      '555-2222',               'Complex phone 2 preserved');
  is(scalar(keys %{$decoded->attributes()}), 3,                        'Complex attributes count preserved');
  is($decoded->attributes()->{department},   'Research',               'Complex attribute preserved');
  is($decoded->which_permission(),           'permissions',            'Complex oneof preserved');
  is(scalar(@{$decoded->permissions()}),     4,                        'Complex permissions count preserved');

  # Verify unknown fields preserved
  ok(exists $decoded->{_unknown}, 'Complex unknown fields exist');
  is(scalar(keys %{$decoded->{_unknown}}), 5, 'All unknown fields preserved');

  # Round-trip test
  my $reencoded = $decoded->encode();
  my $redecoded = Example::Person->decode($reencoded);

  # Verify everything is still there
  is($redecoded->name(),                     'Complex Unknown Person', 'Complex round-trip name');
  is(scalar(@{$redecoded->permissions()}),   4,                        'Complex round-trip permissions');
  is(scalar(keys %{$redecoded->{_unknown}}), 5,                        'Complex round-trip unknown fields');
};

# Test unknown fields don't interfere with oneof behavior
subtest 'Unknown fields and oneof interaction' => sub {
  my $person = Example::Person->new(
    name     => 'Oneof Unknown Test',
    is_admin => 1
  );

  my $encoded = $person->encode();

  # Add unknown field
  my $unknown              = _encode_tag(200, 2) . _encode_string("oneof test unknown");
  my $encoded_with_unknown = $encoded . $unknown;

  my $decoded = Example::Person->decode($encoded_with_unknown);

  # Verify oneof still works correctly
  is($decoded->which_permission(), 'is_admin', 'Oneof works with unknown fields');
  ok($decoded->has_is_admin(),     'has_is_admin works with unknown fields');
  ok(!$decoded->has_permissions(), 'has_permissions works with unknown fields');

  # Change oneof field
  $decoded->permissions([ 'test', 'permission' ]);

  # Verify oneof change worked
  is($decoded->which_permission(), 'permissions', 'Oneof change works with unknown fields');
  ok(!$decoded->has_is_admin(),   'Oneof change clears is_admin with unknown fields');
  ok($decoded->has_permissions(), 'Oneof change sets permissions with unknown fields');

  # Verify unknown fields still preserved
  ok(exists $decoded->{_unknown}, 'Unknown fields preserved after oneof change');

  # Re-encode and decode
  my $reencoded = $decoded->encode();
  my $redecoded = Example::Person->decode($reencoded);

  # Verify everything
  is($redecoded->which_permission(), 'permissions', 'Round-trip oneof after change');
  is_deeply($redecoded->permissions(), [ 'test', 'permission' ], 'Round-trip permissions after change');
  ok(exists $redecoded->{_unknown}, 'Round-trip unknown fields after oneof change');
};

# Test empty message with only unknown fields
subtest 'Empty message with unknown fields' => sub {

  # Start with empty message
  my $person  = Example::Person->new();
  my $encoded = $person->encode();

  # Should be empty or very small
  ok(length($encoded) < 10, 'Empty message is small');

  # Add only unknown fields
  my $unknown_only = '';
  $unknown_only .= _encode_tag(999,  0) . _encode_varint(12345);
  $unknown_only .= _encode_tag(1000, 2) . _encode_string("only unknown");

  my $decoded = Example::Person->decode($unknown_only);

  # Verify no known fields are set
  is($decoded->name(),             undef, 'No known fields in unknown-only message');
  is($decoded->id(),               undef, 'No known fields in unknown-only message');
  is($decoded->which_permission(), undef, 'No oneof set in unknown-only message');

  # Verify unknown fields are preserved
  ok(exists $decoded->{_unknown},              'Unknown-only fields preserved');
  ok(scalar(keys %{$decoded->{_unknown}}) > 0, 'Unknown-only fields present');

  # Re-encode should produce the same result
  my $reencoded = $decoded->encode();
  ok(length($reencoded) > 0, 'Unknown-only message re-encodes');

  my $redecoded = Example::Person->decode($reencoded);
  ok(exists $redecoded->{_unknown}, 'Unknown-only round-trip works');
};

# Helper functions to manually create protocol buffer wire format
sub _encode_tag {
  my ($field_num, $wire_type) = @_;
  return _encode_varint(($field_num << 3) | $wire_type);
}

sub _encode_varint {
  my ($value) = @_;
  my $result = '';

  while ($value >= 0x80) {
    $result .= chr(($value & 0x7F) | 0x80);
    $value >>= 7;
  }
  $result .= chr($value & 0x7F);

  return $result;
}

sub _encode_string {
  my ($string) = @_;
  return _encode_varint(length($string)) . $string;
}

sub _encode_bytes {
  my ($bytes) = @_;
  return _encode_varint(length($bytes)) . $bytes;
}

done_testing();
