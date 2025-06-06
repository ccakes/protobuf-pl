#!/usr/bin/env perl

use strict;
use warnings;
use lib qw(lib generated);

print "Testing basic functionality...\n";

# Test the basic functionality of the generated code
use Example::Person;
use Example::Status;

print "Modules loaded successfully.\n";

# Test enum values
print "UNKNOWN = " . Example::Status::UNKNOWN . "\n";
print "ACTIVE = " . Example::Status::ACTIVE . "\n";
print "INACTIVE = " . Example::Status::INACTIVE . "\n";

# Test message creation and accessors
my $person = Example::Person->new();
print "Person object created: " . ref($person) . "\n";

# Test field accessors
$person->name('John Doe');
print "Name set to: " . $person->name() . "\n";

$person->id(123);
print "ID set to: " . $person->id() . "\n";

$person->email('john@example.com');
print "Email set to: " . $person->email() . "\n";

# Test repeated field
$person->phone_numbers(['555-1234', '555-5678']);
my $phones = $person->phone_numbers();
print "Phone numbers: " . join(', ', @$phones) . "\n";

# Test encoding and decoding
print "Testing encoding...\n";
my $encoded = $person->encode();
print "Encoded length: " . length($encoded) . " bytes\n";

print "Testing decoding...\n";
my $decoded = Example::Person->decode($encoded);
print "Decoded name: " . $decoded->name() . "\n";
print "Decoded ID: " . $decoded->id() . "\n";
print "Decoded email: " . $decoded->email() . "\n";

# Test to_hash and from_hash
print "Testing to_hash...\n";
my $hash = $person->to_hash();
print "Hash keys: " . join(', ', keys %$hash) . "\n";

print "Testing from_hash...\n";
my $from_hash = Example::Person->from_hash($hash);
print "from_hash name: " . $from_hash->name() . "\n";

print "All tests completed!\n";
