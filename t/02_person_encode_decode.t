#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use Example::Person;
use Example::Person::PhoneNumber;
use Example::Person::PhoneType;
use Example::Status;

# Test encode/decode round trip with all fields
subtest 'Encode/decode round trip - all fields with is_admin' => sub {

  # Create a person with all fields set, using is_admin oneof
  my $phone1 = Example::Person::PhoneNumber->new(
    number => '555-1234',
    type   => Example::Person::PhoneType::HOME
  );

  my $phone2 = Example::Person::PhoneNumber->new(
    number => '555-5678',
    type   => Example::Person::PhoneType::MOBILE
  );

  my $original = Example::Person->new(
    name       => 'Alice Smith',
    id         => 12345,
    email      => 'alice@example.com',
    phones     => [ $phone1, $phone2 ],
    attributes => {
      'department' => 'Engineering',
      'location'   => 'San Francisco',
      'level'      => 'Senior'
    },
    is_admin => 1
  );

  # Verify original state
  is($original->which_permission(), 'is_admin', 'Original has is_admin set');
  ok($original->has_is_admin(),     'Original has_is_admin true');
  ok(!$original->has_permissions(), 'Original has_permissions false');

  # Encode to binary
  my $encoded = $original->encode();
  ok(defined $encoded && length($encoded) > 0, 'Encoding produces non-empty binary data');

  # Decode from binary
  my $decoded = Example::Person->decode($encoded);
  isa_ok($decoded, 'Example::Person');

  # Verify all fields match
  is($decoded->name(),  'Alice Smith',       'Name matches after decode');
  is($decoded->id(),    12345,               'ID matches after decode');
  is($decoded->email(), 'alice@example.com', 'Email matches after decode');

  # Verify phones
  is(scalar(@{$decoded->phones()}),     2,                                  'Phones array length matches');
  is($decoded->phones()->[0]->number(), '555-1234',                         'First phone number matches');
  is($decoded->phones()->[0]->type(),   Example::Person::PhoneType::HOME,   'First phone type matches');
  is($decoded->phones()->[1]->number(), '555-5678',                         'Second phone number matches');
  is($decoded->phones()->[1]->type(),   Example::Person::PhoneType::MOBILE, 'Second phone type matches');

  # Verify attributes (map field)
  is_deeply(
    $decoded->attributes(),
    {
      'department' => 'Engineering',
      'location'   => 'San Francisco',
      'level'      => 'Senior'
    },
    'Attributes map matches after decode'
  );

  # Verify oneof field
  is($decoded->which_permission(), 'is_admin', 'Oneof field correctly decoded');
  is($decoded->is_admin(),         1,          'is_admin value matches');
  ok($decoded->has_is_admin(),     'has_is_admin true after decode');
  ok(!$decoded->has_permissions(), 'has_permissions false after decode');
};

# Test encode/decode round trip with permissions oneof
subtest 'Encode/decode round trip - all fields with permissions' => sub {

  # Create a person with all fields set, using permissions oneof
  my $phone = Example::Person::PhoneNumber->new(
    number => '555-9999',
    type   => Example::Person::PhoneType::WORK
  );

  my $original = Example::Person->new(
    name        => 'Bob Johnson',
    id          => 67890,
    email       => 'bob@example.com',
    phones      => [$phone],
    attributes  => {'team' => 'Backend'},
    permissions => [ 'read', 'write', 'execute' ]
  );

  # Verify original state
  is($original->which_permission(), 'permissions', 'Original has permissions set');
  ok(!$original->has_is_admin(),   'Original has_is_admin false');
  ok($original->has_permissions(), 'Original has_permissions true');

  # Encode to binary
  my $encoded = $original->encode();
  ok(defined $encoded && length($encoded) > 0, 'Encoding produces non-empty binary data');

  # Decode from binary
  my $decoded = Example::Person->decode($encoded);
  isa_ok($decoded, 'Example::Person');

  # Verify all fields match
  is($decoded->name(),  'Bob Johnson',     'Name matches after decode');
  is($decoded->id(),    67890,             'ID matches after decode');
  is($decoded->email(), 'bob@example.com', 'Email matches after decode');

  # Verify phone
  is(scalar(@{$decoded->phones()}),     1,                                'Phones array length matches');
  is($decoded->phones()->[0]->number(), '555-9999',                       'Phone number matches');
  is($decoded->phones()->[0]->type(),   Example::Person::PhoneType::WORK, 'Phone type matches');

  # Verify attributes
  is_deeply($decoded->attributes(), {'team' => 'Backend'}, 'Attributes map matches');

  # Verify oneof field
  is($decoded->which_permission(), 'permissions', 'Oneof field correctly decoded');
  is_deeply($decoded->permissions(), [ 'read', 'write', 'execute' ], 'permissions value matches');
  ok(!$decoded->has_is_admin(),   'has_is_admin false after decode');
  ok($decoded->has_permissions(), 'has_permissions true after decode');
};

# Test encode/decode with minimal data
subtest 'Encode/decode round trip - minimal data' => sub {
  my $original = Example::Person->new(name => 'Minimal Person');

  my $encoded = $original->encode();
  my $decoded = Example::Person->decode($encoded);

  is($decoded->name(),  'Minimal Person', 'Name matches in minimal case');
  is($decoded->id(),    undef,            'ID is undef in minimal case');
  is($decoded->email(), undef,            'Email is undef in minimal case');
  is_deeply($decoded->phones(),     [], 'Phones is empty array in minimal case');
  is_deeply($decoded->attributes(), {}, 'Attributes is empty hash in minimal case');
  is($decoded->which_permission(), undef, 'No oneof field set in minimal case');
};

# Test encode/decode with empty string and zero values
subtest 'Encode/decode with empty and zero values' => sub {
  my $original = Example::Person->new(
    name     => '',    # empty string
    id       => 0,     # zero value
    email    => '',    # empty string
    is_admin => 0      # false boolean
  );

  my $encoded = $original->encode();
  my $decoded = Example::Person->decode($encoded);

  is($decoded->name(),             '',         'Empty name preserved');
  is($decoded->id(),               0,          'Zero ID preserved');
  is($decoded->email(),            '',         'Empty email preserved');
  is($decoded->is_admin(),         0,          'False is_admin preserved');
  is($decoded->which_permission(), 'is_admin', 'Oneof still set for false boolean');
};

# Test length-delimited encoding
subtest 'Length-delimited encoding' => sub {
  my $person = Example::Person->new(name => 'Test Person');

  my $length_delimited = $person->encode_length_delimited();
  ok(defined $length_delimited && length($length_delimited) > 0, 'Length-delimited encoding works');

  # The length-delimited format should be longer than plain encoding
  # due to the length prefix
  my $plain_encoded = $person->encode();
  ok(length($length_delimited) > length($plain_encoded), 'Length-delimited is longer than plain');
};

# Test to_hash and from_hash
subtest 'Hash conversion' => sub {
  my $phone = Example::Person::PhoneNumber->new(
    number => '555-HASH',
    type   => Example::Person::PhoneType::HOME
  );

  my $original = Example::Person->new(
    name       => 'Hash Person',
    id         => 99999,
    phones     => [$phone],
    attributes => {'test' => 'hash'},
    is_admin   => 1
  );

  my $hash = $original->to_hash();
  is(ref $hash,         'HASH',        'to_hash returns hash reference');
  is($hash->{name},     'Hash Person', 'Hash contains name');
  is($hash->{id},       99999,         'Hash contains id');
  is($hash->{is_admin}, 1,             'Hash contains is_admin');

  my $reconstructed = Example::Person->from_hash($hash);
  isa_ok($reconstructed, 'Example::Person');
  is($reconstructed->name(),     'Hash Person', 'Reconstructed name matches');
  is($reconstructed->id(),       99999,         'Reconstructed id matches');
  is($reconstructed->is_admin(), 1,             'Reconstructed is_admin matches');
};

# Test invalid data handling
subtest 'Invalid data handling' => sub {

  # Test decoding empty buffer
  my $empty_decoded = Example::Person->decode('');
  isa_ok($empty_decoded, 'Example::Person');
  is($empty_decoded->name(), undef, 'Empty decode produces valid but empty object');

  # Test constructor with invalid field
  eval { Example::Person->new(invalid_field => 'should fail'); };
  ok($@, 'Constructor rejects invalid field names');
  like($@, qr/Unknown field/, 'Error message mentions unknown field');
};

done_testing();
