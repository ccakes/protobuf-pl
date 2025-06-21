#!/usr/bin/env perl
use strict;
use warnings;

use lib qw(lib generated);

use Conformance::ConformanceRequest;
use Conformance::ConformanceResponse;
use ProtobufTestMessages::Proto3::TestAllTypesProto3;

use Proto::PL::Runtime;

use DDP;

binmode(STDIN,  ':raw');
binmode(STDOUT, ':raw');

STDOUT->autoflush;

sub read_length_delimited_message {
  my $fh = shift;
  my $len_bytes;
  read($fh, $len_bytes, 4) == 4 or return;
  my $len = unpack("V", $len_bytes);    # little-endian 32-bit
  my $data;
  read($fh, $data, $len) == $len or die "Failed to read message of length $len";
  return $data;
}

sub write_length_delimited_message {
  my ($fh, $data) = @_;
  print $fh pack("V", length($data));
  print $fh $data;
}

my $test_case = 0;
while (1) {
  $test_case++;
  my $input = read_length_delimited_message(\*STDIN);
  last unless defined $input;

  my $response = Conformance::ConformanceResponse->new;

  my $request = eval { Conformance::ConformanceRequest->decode($input) };
  if ($@) {
    $response->parse_error("Failed to decode request: $@");
    write_length_delimited_message(\*STDOUT, $response->encode);
    next;
  }

  if (!$request->has_protobuf_payload) {
    $response->skipped("Only protobuf_payload is supported in this runner");
    write_length_delimited_message(\*STDOUT, $response->encode);
    next;
  }

  # Handle the message types.
  if ($request->message_type eq "protobuf_test_messages.proto3.TestAllTypesProto3") {
    my $test_message = eval { ProtobufTestMessages::Proto3::TestAllTypesProto3->decode($request->protobuf_payload) };
    if ($@) {
      $response->parse_error("Failed to decode TestAllTypesProto3: $@");
      write_length_delimited_message(\*STDOUT, $response->encode);
      next;
    }

    # Here you can process the test_message as needed.
    # For demonstration, let's just echo it back.
    $response->protobuf_payload($test_message->encode);
  }
  else {
    $response->skipped("Unsupported message type: " . $request->message_type);
  }

  # say STDERR sprintf("test_case: %s (%s)", $test_case, $request->message_type);;

  # # Example: Only handle protobuf_payload and protobuf_output
  # if ($request->has_protobuf_payload) {
  #     # Here you would decode the payload, process it, and re-encode
  #     # For demonstration, just echo back the payload
  #     $response->protobuf_payload($request->protobuf_payload);
  # } else {
  #     # $response->{result_case} = 'skipped';
  #     $response->skipped("Only protobuf_payload is supported in this runner");
  # }

  write_length_delimited_message(\*STDOUT, $response->encode);
} ## end while (1)
