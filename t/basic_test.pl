#!/usr/bin/env perl

use strict;
use warnings;
use lib qw(lib generated);
use Test::More;

# Test the basic functionality of the generated code
use Example::Person;
use Example::Status;

# Test enum values
is(Example::Status::UNKNOWN, 0, 'UNKNOWN enum value');
is(Example::Status::ACTIVE, 1, 'ACTIVE enum value');
is(Example::Status::INACTIVE, 2, 'INACTIVE enum value');

# Test message creation and accessors
my $person = Example::Person->new();
isa_ok($person, 'Example::Person', 'Person object creation');
isa_ok($person, 'Proto::PL::Runtime::Message', 'Person inherits from Message');

# Test field accessors
$person->name('John Doe');
is($person->name(), 'John Doe', 'Name accessor works');

$person->id(123);
is($person->id(), 123, 'ID accessor works');

$person->email('john@example.com');
is($person->email(), 'john@example.com', 'Email accessor works');

# Test repeated field
$person->phone_numbers(['555-1234', '555-5678']);
is_deeply($person->phone_numbers(), ['555-1234', '555-5678'], 'Phone numbers repeated field');

# Test encoding and decoding
my $encoded = $person->encode();
ok(defined $encoded && length($encoded) > 0, 'Encoding produces non-empty data');

my $decoded = Example::Person->decode($encoded);
isa_ok($decoded, 'Example::Person', 'Decoded object is correct type');
is($decoded->name(), 'John Doe', 'Decoded name matches');
is($decoded->id(), 123, 'Decoded ID matches');
is($decoded->email(), 'john@example.com', 'Decoded email matches');
is_deeply($decoded->phone_numbers(), ['555-1234', '555-5678'], 'Decoded phone numbers match');

# Test to_hash and from_hash
my $hash = $person->to_hash();
is(ref($hash), 'HASH', 'to_hash returns hash reference');
is($hash->{name}, 'John Doe', 'Hash contains name');
is($hash->{id}, 123, 'Hash contains ID');

my $from_hash = Example::Person->from_hash($hash);
isa_ok($from_hash, 'Example::Person', 'from_hash creates correct object');
is($from_hash->name(), 'John Doe', 'from_hash preserves name');
is($from_hash->id(), 123, 'from_hash preserves ID');

print "All basic tests passed!\n";
done_testing();
