#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use Example::Person;
use Example::Status;

# Test integration between Person and Status (enum usage)
subtest 'Status enum integration' => sub {

  # Test using Status enum values
  is(Example::Status::UNKNOWN,  0, 'Status UNKNOWN value');
  is(Example::Status::ACTIVE,   1, 'Status ACTIVE value');
  is(Example::Status::INACTIVE, 2, 'Status INACTIVE value');

  # Create a person with status information in attributes
  my $person = Example::Person->new(
    name       => 'Status Test Person',
    id         => 42,
    attributes => {
      'status'          => Example::Status::ACTIVE,
      'previous_status' => Example::Status::INACTIVE,
      'status_name'     => 'ACTIVE'
    }
  );

  is($person->attributes()->{status},          Example::Status::ACTIVE,   'Status enum stored in attributes');
  is($person->attributes()->{previous_status}, Example::Status::INACTIVE, 'Previous status stored');

  # Test encoding/decoding with enum values
  my $encoded = $person->encode();
  my $decoded = Example::Person->decode($encoded);

  is($decoded->attributes()->{status},          Example::Status::ACTIVE,   'Status enum survives encoding');
  is($decoded->attributes()->{previous_status}, Example::Status::INACTIVE, 'Previous status survives encoding');
};

# Test complete workflow with all features
subtest 'Complete workflow integration test' => sub {

  # Create complex person with all features
  my $home_phone = Example::Person::PhoneNumber->new(
    number => '555-HOME',
    type   => Example::Person::PhoneType::HOME
  );

  my $work_phone = Example::Person::PhoneNumber->new(
    number => '555-WORK',
    type   => Example::Person::PhoneType::WORK
  );

  my $mobile_phone = Example::Person::PhoneNumber->new(
    number => '555-MOBILE',
    type   => Example::Person::PhoneType::MOBILE
  );

  my $person = Example::Person->new(
    name       => 'Integration Test Person',
    id         => 12345,
    email      => 'integration@test.com',
    phones     => [ $home_phone, $work_phone, $mobile_phone ],
    attributes => {
      'department'         => 'Engineering',
      'office_location'    => 'Building A',
      'employee_level'     => 'Senior',
      'status'             => Example::Status::ACTIVE,
      'hire_date'          => '2024-01-15',
      'security_clearance' => 'Level 3'
    },
    is_admin => 1
  );

  # Verify initial state
  is($person->name(),                       'Integration Test Person', 'Initial name correct');
  is($person->which_permission(),           'is_admin',                'Initial oneof correct');
  is(scalar(@{$person->phones()}),          3,                         'All phones present');
  is(scalar(keys %{$person->attributes()}), 6,                         'All attributes present');

  # Test first encoding round trip
  my $encoded1 = $person->encode();
  ok(length($encoded1) > 100, 'Complex message has substantial size');

  my $decoded1 = Example::Person->decode($encoded1);
  is($decoded1->name(),                 'Integration Test Person', 'Round trip 1: name preserved');
  is($decoded1->which_permission(),     'is_admin',                'Round trip 1: oneof preserved');
  is($decoded1->attributes()->{status}, Example::Status::ACTIVE,   'Round trip 1: enum preserved');

  # Modify the oneof field
  $decoded1->permissions([ 'read', 'write', 'admin', 'super_user' ]);
  is($decoded1->which_permission(), 'permissions', 'Oneof changed to permissions');
  ok(!$decoded1->has_is_admin(),   'is_admin cleared by oneof change');
  ok($decoded1->has_permissions(), 'permissions set by oneof change');

  # Test second encoding round trip
  my $encoded2 = $decoded1->encode();
  my $decoded2 = Example::Person->decode($encoded2);

  is($decoded2->name(),             'Integration Test Person', 'Round trip 2: name preserved');
  is($decoded2->which_permission(), 'permissions',             'Round trip 2: oneof change preserved');
  is_deeply($decoded2->permissions(), [ 'read', 'write', 'admin', 'super_user' ], 'Round trip 2: permissions preserved');
  is($decoded2->attributes()->{status}, Example::Status::ACTIVE, 'Round trip 2: enum still preserved');

  # Modify attributes and add more phones
  $decoded2->attributes()->{status}            = Example::Status::INACTIVE;
  $decoded2->attributes()->{modification_date} = '2024-06-07';

  my $emergency_phone = Example::Person::PhoneNumber->new(
    number => '555-EMERGENCY',
    type   => Example::Person::PhoneType::MOBILE
  );

  push @{$decoded2->phones()}, $emergency_phone;

  # Test third encoding round trip
  my $encoded3 = $decoded2->encode();
  my $decoded3 = Example::Person->decode($encoded3);

  is($decoded3->attributes()->{status},            Example::Status::INACTIVE, 'Round trip 3: status change preserved');
  is($decoded3->attributes()->{modification_date}, '2024-06-07',              'Round trip 3: new attribute preserved');
  is(scalar(@{$decoded3->phones()}),               4,                         'Round trip 3: additional phone preserved');
  is($decoded3->phones()->[3]->number(),           '555-EMERGENCY',           'Round trip 3: emergency phone correct');

  # Convert to hash and back
  my $hash      = $decoded3->to_hash();
  my $from_hash = Example::Person->from_hash($hash);

  is($from_hash->name(),                       'Integration Test Person', 'Hash round trip: name preserved');
  is($from_hash->which_permission(),           'permissions',             'Hash round trip: oneof preserved');
  is(scalar(keys %{$from_hash->attributes()}), 7,                         'Hash round trip: all attributes preserved');
};

# Test error recovery and edge cases in complex scenarios
subtest 'Complex error handling' => sub {
  my $person = Example::Person->new(name => 'Error Test Person');

  # Test setting invalid data types and recovery
  eval {
    $person->phones('not an array');    # Should work but might not be useful
  };

  # This might not throw an error depending on implementation

  # Test with mixed valid/invalid phone numbers
  my $good_phone = Example::Person::PhoneNumber->new(
    number => '555-GOOD',
    type   => Example::Person::PhoneType::HOME
  );

  $person->phones([$good_phone]);

  # Add some attributes with various data types
  $person->attributes({
      'string_val' => 'text',
      'number_val' => 42,
      'zero_val'   => 0,
      'empty_val'  => '',
      'status_val' => Example::Status::ACTIVE,
      'undef_val'  => undef,
    }
  );

  # Should encode/decode successfully even with mixed types
  my $encoded = $person->encode();
  my $decoded = Example::Person->decode($encoded);

  is($decoded->name(),                     'Error Test Person',     'Complex attributes: name preserved');
  is($decoded->attributes()->{string_val}, 'text',                  'Complex attributes: string preserved');
  is($decoded->attributes()->{number_val}, 42,                      'Complex attributes: number preserved');
  is($decoded->attributes()->{zero_val},   0,                       'Complex attributes: zero preserved');
  is($decoded->attributes()->{empty_val},  '',                      'Complex attributes: empty string preserved');
  is($decoded->attributes()->{status_val}, Example::Status::ACTIVE, 'Complex attributes: enum preserved');

  # undef values might not be preserved in protobuf
};

# Test performance with realistic data sizes
subtest 'Performance and realistic data' => sub {
  my @realistic_phones;

  # Create realistic phone numbers
  push @realistic_phones,
    Example::Person::PhoneNumber->new(
    number => '+1-555-123-4567',
    type   => Example::Person::PhoneType::HOME
    );

  push @realistic_phones,
    Example::Person::PhoneNumber->new(
    number => '+1-555-987-6543',
    type   => Example::Person::PhoneType::WORK
    );

  push @realistic_phones,
    Example::Person::PhoneNumber->new(
    number => '+1-555-555-5555',
    type   => Example::Person::PhoneType::MOBILE
    );

  # Create realistic attributes
  my %realistic_attrs = (
    'employee_id'        => 'EMP-2023-001234',
    'department'         => 'Software Engineering',
    'team'               => 'Backend Infrastructure',
    'manager'            => 'Jane Smith',
    'office_location'    => 'San Francisco, CA - Building 3, Floor 7',
    'hire_date'          => '2023-03-15',
    'last_review_date'   => '2024-03-15',
    'next_review_date'   => '2025-03-15',
    'salary_grade'       => 'L5',
    'status'             => Example::Status::ACTIVE,
    'security_clearance' => 'Standard',
    'emergency_contact'  => 'John Doe - +1-555-999-8888',
    'preferred_name'     => 'Alex',
    'pronouns'           => 'they/them',
    'time_zone'          => 'America/Los_Angeles',
    'work_schedule'      => 'Flexible - 9am-5pm core hours'
  );

  my $realistic_person = Example::Person->new(
    name        => 'Alexandra Johnson-Smith',
    id          => 2024001234,
    email       => 'alexandra.johnson-smith@company.example.com',
    phones      => \@realistic_phones,
    attributes  => \%realistic_attrs,
    permissions => [ 'user.read', 'user.write', 'project.read', 'project.write', 'team.lead', 'code.review', 'deployment.staging' ]
  );

  # Test encoding performance and size
  my $start_time  = time();
  my $encoded     = $realistic_person->encode();
  my $encode_time = time() - $start_time;

  ok($encode_time < 1,         'Realistic message encodes quickly');
  ok(length($encoded) > 200,   'Realistic message has reasonable size');
  ok(length($encoded) < 10000, 'Realistic message is not excessive');

  # Test decoding performance
  $start_time = time();
  my $decoded     = Example::Person->decode($encoded);
  my $decode_time = time() - $start_time;

  ok($decode_time < 1, 'Realistic message decodes quickly');

  # Verify all data is preserved
  is($decoded->name(), 'Alexandra Johnson-Smith', 'Realistic: name preserved');
  is($decoded->id(),   2024001234,                'Realistic: id preserved');
  like($decoded->email(), qr/alexandra\.johnson-smith/, 'Realistic: email preserved');
  is(scalar(@{$decoded->phones()}),          3,             'Realistic: all phones preserved');
  is(scalar(keys %{$decoded->attributes()}), 16,            'Realistic: all attributes preserved');
  is(scalar(@{$decoded->permissions()}),     7,             'Realistic: all permissions preserved');
  is($decoded->which_permission(),           'permissions', 'Realistic: oneof preserved');

  # Test specific attribute values
  is($decoded->attributes()->{department}, 'Software Engineering',  'Realistic: department preserved');
  is($decoded->attributes()->{status},     Example::Status::ACTIVE, 'Realistic: enum status preserved');
  like($decoded->attributes()->{office_location}, qr/San Francisco/, 'Realistic: complex attribute preserved');
};

done_testing();
