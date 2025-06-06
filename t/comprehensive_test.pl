#!/usr/bin/env perl

use strict;
use warnings;
use lib qw(lib generated);

print "Starting comprehensive test...\n";

use Example::Person;
use Example::Status;

# Test enum values
print "Testing enums...\n";
print "UNKNOWN = " . Example::Status::UNKNOWN . "\n";
print "ACTIVE = " . Example::Status::ACTIVE . "\n";
print "INACTIVE = " . Example::Status::INACTIVE . "\n";

# Test message creation and accessors
print "\nTesting message creation...\n";
my $person = Example::Person->new();
print "Person object created: " . ref($person) . "\n";

# Test field accessors
print "\nTesting field accessors...\n";
$person->name('John Doe');
print "Name set to: " . ($person->name() || 'undef') . "\n";

$person->id(123);
print "ID set to: " . ($person->id() || 'undef') . "\n";

$person->email('john@example.com');
print "Email set to: " . ($person->email() || 'undef') . "\n";

# Test repeated field
print "\nTesting repeated fields...\n";
$person->phone_numbers(['555-1234', '555-5678']);
my $phones = $person->phone_numbers();
if ($phones && ref($phones) eq 'ARRAY') {
    print "Phone numbers: " . join(', ', @$phones) . "\n";
} else {
    print "Phone numbers: undef or not array\n";
}

# Test encoding and decoding
print "\nTesting encoding...\n";
eval {
    my $encoded = $person->encode();
    print "Encoded length: " . length($encoded) . " bytes\n";
    
    print "Testing decoding...\n";
    my $decoded = Example::Person->decode($encoded);
    print "Decoded name: " . ($decoded->name() || 'undef') . "\n";
    print "Decoded ID: " . ($decoded->id() || 'undef') . "\n";
    print "Decoded email: " . ($decoded->email() || 'undef') . "\n";
};
if ($@) {
    print "Error in encode/decode: $@\n";
}

# Test to_hash and from_hash
print "\nTesting to_hash/from_hash...\n";
eval {
    my $hash = $person->to_hash();
    if ($hash && ref($hash) eq 'HASH') {
        print "Hash keys: " . join(', ', keys %$hash) . "\n";
        
        my $from_hash = Example::Person->from_hash($hash);
        print "from_hash name: " . ($from_hash->name() || 'undef') . "\n";
    } else {
        print "to_hash didn't return a hash reference\n";
    }
};
if ($@) {
    print "Error in to_hash/from_hash: $@\n";
}

print "\nAll tests completed!\n";
