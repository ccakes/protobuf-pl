#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use File::Temp qw(tempfile);
use IO::Socket::INET;
use POSIX qw(mkfifo);
use Fcntl qw(O_NONBLOCK);

use Example::Person;
use Example::Person::PhoneNumber;
use Example::Person::PhoneType;

# Test UDP socket communication
subtest 'UDP socket communication' => sub {
  plan skip_all => 'UDP socket tests require available ports' unless _can_bind_udp();

  # Create test data
  my $phone = Example::Person::PhoneNumber->new(
    number => '555-UDP1',
    type   => Example::Person::PhoneType::MOBILE
  );

  my $original = Example::Person->new(
    name       => 'UDP Person',
    id         => 11111,
    email      => 'udp@example.com',
    phones     => [$phone],
    attributes => {'transport' => 'UDP'},
    is_admin   => 1
  );

  # Create UDP sockets
  my $server_port = _find_free_port();
  diag "Using UDP port: $server_port";
  my $server = IO::Socket::INET->new(
    LocalAddr => 'localhost',
    LocalPort => $server_port,
    Proto     => 'udp',
    ReuseAddr => 1
  ) or skip "Cannot create UDP server socket: $!", 1;

  my $client = IO::Socket::INET->new(
    LocalAddr => 'localhost',
    PeerAddr  => 'localhost',
    PeerPort  => $server_port,
    Proto     => 'udp'
  ) or skip "Cannot create UDP client socket: $!", 1;

  # Encode and send data
  my $encoded = $original->encode();
  my $sent    = $client->send($encoded);
  ok(defined $sent && $sent > 0, 'Data sent via UDP');

  # Receive and decode data
  my $buffer;
  my $received = $server->recv($buffer, 4096);
  ok(defined $received, 'Data received via UDP');

  my $decoded = Example::Person->decode($buffer);
  isa_ok($decoded, 'Example::Person');

  # Verify data integrity
  is($decoded->name(),                  'UDP Person',      'Name preserved over UDP');
  is($decoded->id(),                    11111,             'ID preserved over UDP');
  is($decoded->email(),                 'udp@example.com', 'Email preserved over UDP');
  is($decoded->phones()->[0]->number(), '555-UDP1',        'Phone preserved over UDP');
  is($decoded->is_admin(),              1,                 'is_admin preserved over UDP');
  is($decoded->which_permission(),      'is_admin',        'Oneof preserved over UDP');
  is_deeply($decoded->attributes(), {'transport' => 'UDP'}, 'Attributes preserved over UDP');

  # Test with permissions oneof
  my $original2 = Example::Person->new(
    name        => 'UDP Person 2',
    id          => 22222,
    permissions => [ 'udp', 'read', 'write' ]
  );

  my $encoded2 = $original2->encode();
  $client->send($encoded2);

  $server->recv($buffer, 4096);
  my $decoded2 = Example::Person->decode($buffer);

  is($decoded2->name(),             'UDP Person 2', 'Second message name preserved');
  is($decoded2->which_permission(), 'permissions',  'Second message oneof preserved');
  is_deeply($decoded2->permissions(), [ 'udp', 'read', 'write' ], 'Second message permissions preserved');

  $server->close();
  $client->close();
};

# Test named pipe communication
subtest 'Named pipe communication' => sub {
  plan skip_all => 'Named pipes not supported on this system' unless _supports_named_pipes();

  # Create test data
  my $phone = Example::Person::PhoneNumber->new(
    number => '555-PIPE',
    type   => Example::Person::PhoneType::WORK
  );

  my $original = Example::Person->new(
    name        => 'Pipe Person',
    id          => 33333,
    email       => 'pipe@example.com',
    phones      => [$phone],
    attributes  => {'transport' => 'Named Pipe', 'mode' => 'test'},
    permissions => [ 'pipe', 'read' ]
  );

  # Create temporary named pipe
  my $pipe_name = "/tmp/protoc_test_pipe_$$";

  # Clean up any existing pipe
  unlink $pipe_name if -e $pipe_name;

  # Create named pipe
  unless (mkfifo($pipe_name, 0600)) {
    skip "Cannot create named pipe: $!", 1;
  }

  # Fork process for pipe communication
  my $pid = fork();
  if (!defined $pid) {
    skip "Cannot fork: $!", 1;
  }

  if ($pid == 0) {

    # Child process - writer
    sleep 1;    # Give parent time to open for reading

    open my $pipe_write, '>', $pipe_name or exit 1;
    binmode $pipe_write;

    my $encoded = $original->encode();
    print $pipe_write $encoded;
    close $pipe_write;
    exit 0;
  }
  else {
    # Parent process - reader
    open my $pipe_read, '<', $pipe_name or do {
      kill 'TERM', $pid;
      waitpid $pid, 0;
      unlink $pipe_name;
      skip "Cannot open pipe for reading: $!", 1;
    };
    binmode $pipe_read;

    my $buffer;
    read $pipe_read, $buffer, 4096;
    close $pipe_read;

    # Wait for child to complete
    waitpid $pid, 0;

    # Clean up
    unlink $pipe_name;

    # Decode and verify
    my $decoded = Example::Person->decode($buffer);
    isa_ok($decoded, 'Example::Person');

    is($decoded->name(),                  'Pipe Person',      'Name preserved over named pipe');
    is($decoded->id(),                    33333,              'ID preserved over named pipe');
    is($decoded->email(),                 'pipe@example.com', 'Email preserved over named pipe');
    is($decoded->phones()->[0]->number(), '555-PIPE',         'Phone preserved over named pipe');
    is($decoded->which_permission(),      'permissions',      'Oneof preserved over named pipe');
    is_deeply($decoded->permissions(), [ 'pipe', 'read' ], 'Permissions preserved over named pipe');
    is_deeply(
      $decoded->attributes(),
      {
        'transport' => 'Named Pipe',
        'mode'      => 'test'
      },
      'Attributes preserved over named pipe'
    );
  } ## end else [ if ($pid == 0) ]
};

# Test large message over UDP (fragmentation edge case)
subtest 'Large message over UDP' => sub {
  plan skip_all => 'UDP socket tests require available ports' unless _can_bind_udp();

  # Create a large message with many phones and attributes
  my @phones;
  for my $i (1 .. 50) {
    push @phones, Example::Person::PhoneNumber->new(
      number => "555-LARGE-$i",
      type   => $i % 3            # Cycle through phone types
    );
  }

  my %large_attrs;
  for my $i (1 .. 100) {
    $large_attrs{"key_$i"} = "This is a longer value for key $i to make the message larger";
  }

  my $original = Example::Person->new(
    name        => 'Large Message Person With A Very Long Name That Takes Up More Space',
    id          => 999999,
    email       => 'large.message.with.long.email.address@very.long.domain.example.com',
    phones      => \@phones,
    attributes  => \%large_attrs,
    permissions => [ map {"permission_$_"} (1 .. 20) ]
  );

  my $server_port = _find_free_port();
  my $server      = IO::Socket::INET->new(
    LocalPort => $server_port,
    Proto     => 'udp',
    ReuseAddr => 1
  ) or skip "Cannot create UDP server socket: $!", 1;

  my $client = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1',
    PeerPort => $server_port,
    Proto    => 'udp'
  ) or skip "Cannot create UDP client socket: $!", 1;

  my $encoded = $original->encode();
  ok(length($encoded) > 1000, 'Large message is actually large');

  # Send the large message
  my $sent = $client->send($encoded);
  ok(defined $sent && $sent > 0, 'Large message sent via UDP');

  # Receive with larger buffer
  my $buffer;
  my $received = $server->recv($buffer, 65536);
  ok(defined $received, 'Large message received via UDP');

  my $decoded = Example::Person->decode($buffer);
  isa_ok($decoded, 'Example::Person');

  # Verify key parts of the large message
  like($decoded->name(), qr/Large Message Person/, 'Large message name preserved');
  is($decoded->id(),                         999999, 'Large message ID preserved');
  is(scalar(@{$decoded->phones()}),          50,     'All phones preserved in large message');
  is(scalar(keys %{$decoded->attributes()}), 100,    'All attributes preserved in large message');
  is(scalar(@{$decoded->permissions()}),     20,     'All permissions preserved in large message');

  $server->close();
  $client->close();
};

# Helper functions
sub _can_bind_udp {
  my $test_socket = IO::Socket::INET->new(
    LocalPort => 0,       # Let system choose port
    Proto     => 'udp',
    ReuseAddr => 1
  );

  if ($test_socket) {
    $test_socket->close();
    return 1;
  }

  return 0;
}

sub _find_free_port {
  my $socket = IO::Socket::INET->new(
    LocalAddr => 'localhost',
    LocalPort => 0,
    Proto     => 'udp',
    ReuseAddr => 1
  ) or return 0;

  my $port = $socket->sockport();
  $socket->close();
  return $port;
}

sub _supports_named_pipes {

  # Check if mkfifo is available and we can create pipes
  eval { mkfifo("/tmp/test_pipe_support_$$", 0600) };
  if ($@) {
    return 0;
  }
  unlink "/tmp/test_pipe_support_$$";
  return 1;
}

done_testing();
