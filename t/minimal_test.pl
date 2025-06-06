#!/usr/bin/env perl

use strict;
use warnings;
use lib qw(lib generated);

print "Starting minimal test...\n";

eval {
    require Example::Person;
    print "Person module loaded\n";
};
if ($@) {
    print "Error loading Person: $@\n";
    exit 1;
}

eval {
    require Example::Status;
    print "Status module loaded\n";
};
if ($@) {
    print "Error loading Status: $@\n";
    exit 1;
}

print "Creating person...\n";
my $person = Example::Person->new();
print "Person created: " . ref($person) . "\n";

print "Test completed successfully!\n";
