#!/usr/bin/env perl

use strict;
use warnings;
use lib qw(lib);

print "Testing varint decoding directly with real data...\n";

use Proto::PL::Runtime;

# Test the exact encoded data from our previous test
my $encoded_data = pack("H*", "107b");
print "Full encoded data: " . unpack("H*", $encoded_data) . "\n";

# Manually decode the tag
my ($tag, $tag_consumed) = Proto::PL::Runtime::_decode_varint($encoded_data, 0);
print "Tag: $tag (0x" . sprintf("%x", $tag) . "), consumed: $tag_consumed bytes\n";

my $field_num = $tag >> 3;
my $wire_type = $tag & 0x07;
print "Field number: $field_num, wire type: $wire_type\n";

# Now decode the value
my $value_start = $tag_consumed;
my $value_data = substr($encoded_data, $value_start);
print "Value data: " . unpack("H*", $value_data) . "\n";

my ($decoded_value, $value_consumed) = Proto::PL::Runtime::_decode_varint($value_data, 0);
print "Decoded value: $decoded_value, consumed: $value_consumed bytes\n";

# Also test with the substr approach that's in the generated code
print "\nTesting with alternative approach...\n";
my ($alt_value, $alt_consumed) = Proto::PL::Runtime::_decode_varint($encoded_data, $value_start);
print "Alternative decoded value: $alt_value, consumed: $alt_consumed bytes\n";

print "\nVarint test completed!\n";
