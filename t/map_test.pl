#!/usr/bin/env perl

use strict;
use warnings;
use lib qw(lib generated);

print "Testing map functionality...\n";

use Example::Person;

# Test map field
my $person = Example::Person->new();
$person->name('John');

# Test map setter/getter
print "Testing map field...\n";
$person->attributes({
    'favorite_color' => 'blue',
    'hometown' => 'Seattle'
});

my $attrs = $person->attributes();
if ($attrs && ref($attrs) eq 'HASH') {
    print "Map contents:\n";
    for my $key (sort keys %$attrs) {
        print "  $key => $attrs->{$key}\n";
    }
} else {
    print "Map field not working properly\n";
}

# Test encoding/decoding with map
print "\nTesting encoding/decoding with map...\n";
eval {
    my $encoded = $person->encode();
    print "Encoded length: " . length($encoded) . " bytes\n";
    
    my $decoded = Example::Person->decode($encoded);
    print "Decoded name: " . ($decoded->name() || 'undef') . "\n";
    
    my $decoded_attrs = $decoded->attributes();
    if ($decoded_attrs && ref($decoded_attrs) eq 'HASH') {
        print "Decoded map contents:\n";
        for my $key (sort keys %$decoded_attrs) {
            print "  $key => $decoded_attrs->{$key}\n";
        }
    } else {
        print "Decoded map not working\n";
    }
};
if ($@) {
    print "Error: $@\n";
}

print "\nMap test completed!\n";
