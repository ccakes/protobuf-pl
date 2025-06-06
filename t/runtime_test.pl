#!/usr/bin/env perl

use strict;
use warnings;
use lib qw(lib);

print "Testing runtime functions directly...\n";

use Proto::PL::Runtime;

# Test varint encoding/decoding
print "\nTesting varint...\n";
my $encoded_123 = Proto::PL::Runtime::_encode_varint(123);
print "Encoded 123 as varint: " . unpack("H*", $encoded_123) . "\n";

my ($decoded, $consumed) = Proto::PL::Runtime::_decode_varint($encoded_123, 0);
print "Decoded back: $decoded, consumed: $consumed bytes\n";

# Test string encoding/decoding
print "\nTesting string...\n";
my $encoded_john = Proto::PL::Runtime::_encode_string("John");
print "Encoded 'John' as string: " . unpack("H*", $encoded_john) . "\n";

# Manually decode string
my ($len, $len_consumed) = Proto::PL::Runtime::_decode_varint($encoded_john, 0);
print "String length: $len, length consumed: $len_consumed\n";

my $string_bytes = substr($encoded_john, $len_consumed, $len);
print "String bytes: " . unpack("H*", $string_bytes) . " = '$string_bytes'\n";

my $decoded_string = Proto::PL::Runtime::_decode_string($string_bytes);
print "Decoded string: '$decoded_string'\n";

print "\nRuntime test completed!\n";
