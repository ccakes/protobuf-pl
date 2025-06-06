#!/usr/bin/env perl

use strict;
use warnings;
use lib qw(lib generated);

print "Testing integer field specifically...\n";

use Example::Person;

# Test just integer encoding/decoding
my $person = Example::Person->new();
$person->id(123);

print "Original ID: " . $person->id() . "\n";

my $encoded = $person->encode();
print "Encoded length: " . length($encoded) . " bytes\n";
print "Encoded data: " . unpack("H*", $encoded) . "\n";

my $decoded = Example::Person->decode($encoded);
print "Decoded ID: " . ($decoded->id() // 'undef') . "\n";

# Test with different values
for my $test_id (1, 49, 123, 255, 1000) {
    $person = Example::Person->new();
    $person->id($test_id);
    
    $encoded = $person->encode();
    $decoded = Example::Person->decode($encoded);
    
    my $result = $decoded->id() // 'undef';
    my $status = ($result == $test_id) ? "✓" : "✗";
    print "ID $test_id -> $result $status\n";
}

print "\nInteger test completed!\n";
