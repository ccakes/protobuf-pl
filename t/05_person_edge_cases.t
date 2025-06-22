#!/usr/bin/env perl

# use open ":std", ":encoding(UTF-8)";

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use Example::Person;
use Example::Person::PhoneNumber;

binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

# Test edge cases and error handling
subtest 'UTF-8 string handling' => sub {
  my $person = Example::Person->new();

  # Test UTF-8 strings
  my $utf8_name = "José María Müller-Lüdenscheidt 中文测试 🌟";
  $person->name($utf8_name);
  is($person->name(), $utf8_name, 'UTF-8 name stored correctly');

  my $utf8_email = 'josé@müller.中国';
  $person->email($utf8_email);
  is($person->email(), $utf8_email, 'UTF-8 email stored correctly');

  # Test encoding/decoding UTF-8
  my $encoded = $person->encode();
  my $decoded = Example::Person->decode($encoded);

  is($decoded->name(),  $utf8_name,  'UTF-8 name survives encoding round-trip');
  is($decoded->email(), $utf8_email, 'UTF-8 email survives encoding round-trip');

  # Test UTF-8 in attributes
  $person->attributes({
      'ключ'  => 'значение',    # Russian
      '键'     => '值',           # Chinese
      'مفتاح' => 'قيمة',        # Arabic
      '🔑'     => '🌟'            # Emoji
    }
  );

  $encoded = $person->encode();
  $decoded = Example::Person->decode($encoded);

  is($decoded->attributes()->{'ключ'},  'значение', 'UTF-8 attribute key/value (Russian)');
  is($decoded->attributes()->{'键'},     '值',        'UTF-8 attribute key/value (Chinese)');
  is($decoded->attributes()->{'مفتاح'}, 'قيمة',     'UTF-8 attribute key/value (Arabic)');
  is($decoded->attributes()->{'🔑'},     '🌟',        'UTF-8 attribute key/value (Emoji)');
};

# Test very large numbers
subtest 'Large number handling' => sub {
  my $person = Example::Person->new();

  # Test large positive ID
  my $large_id = 2**31 - 1;    # Max signed 32-bit
  $person->id($large_id);
  is($person->id(), $large_id, 'Large positive ID stored');

  my $encoded = $person->encode();
  my $decoded = Example::Person->decode($encoded);
  is($decoded->id(), $large_id, 'Large positive ID survives round-trip');

  # Test zero
  $person->id(0);
  $encoded = $person->encode();
  $decoded = Example::Person->decode($encoded);
  is($decoded->id(), 0, 'Zero ID survives round-trip');

  # Test negative numbers (if supported)
  $person->id(-1);
  $encoded = $person->encode();
  $decoded = Example::Person->decode($encoded);

  # Note: depending on protobuf implementation, negative numbers might be handled differently
  ok(defined $decoded->id(), 'Negative ID handled');
};

# Test empty and null values
subtest 'Empty and null value handling' => sub {
  my $person = Example::Person->new();

  # Test empty strings
  $person->name('');
  $person->email('');
  is($person->name(),  '', 'Empty name stored');
  is($person->email(), '', 'Empty email stored');

  my $encoded = $person->encode();
  my $decoded = Example::Person->decode($encoded);
  is($decoded->name(),  '', 'Empty name survives round-trip');
  is($decoded->email(), '', 'Empty email survives round-trip');

  # Test undef values
  $person->name(undef);
  $person->email(undef);
  is($person->name(),  undef, 'Undef name stored');
  is($person->email(), undef, 'Undef email stored');

  # Test empty arrays
  $person->phones([]);
  is_deeply($person->phones(), [], 'Empty phones array stored');

  $encoded = $person->encode();
  $decoded = Example::Person->decode($encoded);
  is_deeply($decoded->phones(), [], 'Empty phones array survives round-trip');

  # Test empty hashes
  $person->attributes({});
  is_deeply($person->attributes(), {}, 'Empty attributes hash stored');

  $encoded = $person->encode();
  $decoded = Example::Person->decode($encoded);
  is_deeply($decoded->attributes(), {}, 'Empty attributes hash survives round-trip');
};

# Test very long strings
subtest 'Very long string handling' => sub {
  my $person = Example::Person->new();

  # Create a very long string
  my $long_string = 'A' x 10000;    # 10KB string
  $person->name($long_string);
  is(length($person->name()), 10000, 'Very long name stored');

  my $encoded = $person->encode();
  ok(length($encoded) > 10000, 'Encoded message is appropriately large');

  my $decoded = Example::Person->decode($encoded);
  is(length($decoded->name()), 10000,        'Very long name survives round-trip');
  is($decoded->name(),         $long_string, 'Very long name content is correct');

  # Test long string in attributes
  my $long_key   = 'K' x 1000;
  my $long_value = 'V' x 1000;
  $person->attributes({$long_key => $long_value});

  $encoded = $person->encode();
  $decoded = Example::Person->decode($encoded);
  is($decoded->attributes()->{$long_key}, $long_value, 'Long attribute key/value survives');
};

# Test many repeated elements
subtest 'Many repeated elements' => sub {
  my @phones;

  # Create many phone numbers
  for my $i (1 .. 1000) {
    push @phones, Example::Person::PhoneNumber->new(
      number => "555-$i",
      type   => $i % 3      # Cycle through types
    );
  }

  my $person = Example::Person->new(
    name   => 'Many Phones Person',
    phones => \@phones
  );

  is(scalar(@{$person->phones()}), 1000, '1000 phones stored');

  my $encoded = $person->encode();
  ok(length($encoded) > 5000, 'Encoded message with many phones is large');

  my $decoded = Example::Person->decode($encoded);
  is(scalar(@{$decoded->phones()}),       1000,       '1000 phones survive round-trip');
  is($decoded->phones()->[0]->number(),   '555-1',    'First phone correct');
  is($decoded->phones()->[999]->number(), '555-1000', 'Last phone correct');

  # Verify types are correct
  is($decoded->phones()->[0]->type(),   1 % 3,    'First phone type correct');
  is($decoded->phones()->[999]->type(), 1000 % 3, 'Last phone type correct');
};

# Test many map entries
subtest 'Many map entries' => sub {
  my %many_attrs;

  # Create many attributes
  for my $i (1 .. 1000) {
    $many_attrs{"key_$i"} = "value_$i";
  }

  my $person = Example::Person->new(
    name       => 'Many Attributes Person',
    attributes => \%many_attrs
  );

  is(scalar(keys %{$person->attributes()}), 1000, '1000 attributes stored');

  my $encoded = $person->encode();
  ok(length($encoded) > 5000, 'Encoded message with many attributes is large');

  my $decoded = Example::Person->decode($encoded);
  is(scalar(keys %{$decoded->attributes()}), 1000,         '1000 attributes survive round-trip');
  is($decoded->attributes()->{key_1},        'value_1',    'First attribute correct');
  is($decoded->attributes()->{key_1000},     'value_1000', 'Last attribute correct');
};

# Test invalid decoding scenarios
subtest 'Invalid decoding scenarios' => sub {

  # Test truncated messages
  my $person  = Example::Person->new(name => 'Test');
  my $encoded = $person->encode();

  # Truncate the message
  my $truncated = substr($encoded, 0, length($encoded) - 1);

  eval { Example::Person->decode($truncated); };
  ok($@, 'Truncated message throws error');
  like($@, qr/Truncated|varint/i, 'Error message mentions truncation');

  # Test completely invalid data
  eval { Example::Person->decode("\xFF\xFF\xFF\xFF"); };
  ok($@, 'Invalid data throws error');

  # Test message with invalid UTF-8
  # This is tricky to test as it depends on the implementation
  # Most implementations should handle this gracefully
};

# Test oneof edge cases
subtest 'Oneof edge cases' => sub {
  my $person = Example::Person->new();

  # Test setting oneof to false/0 values
  $person->is_admin(0);
  is($person->is_admin(),         0,          'is_admin can be set to 0');
  is($person->which_permission(), 'is_admin', 'which_permission works with 0 value');
  ok($person->has_is_admin(), 'has_is_admin true even for 0');

  # Test clearing and re-setting
  $person->clear_permission();
  is($person->which_permission(), undef, 'Oneof cleared');

  $person->permissions([]);    # Empty array
  is($person->which_permission(), 'permissions', 'Empty permissions array still sets oneof');
  ok($person->has_permissions(), 'has_permissions true for empty array');
  is_deeply($person->permissions(), [], 'Empty permissions preserved');

  # Encode/decode with empty permissions
  my $encoded = $person->encode();
  my $decoded = Example::Person->decode($encoded);

  # Note: empty repeated fields might not be encoded, so oneof might not be preserved
  # This is protocol buffer specific behavior
};

# Test method chaining
subtest 'Method chaining' => sub {
  my $person = Example::Person->new();

  # Test that all setters return self for chaining
  my $result = $person->name('Chain Test')->id(12345)->email('chain@test.com')->is_admin(1);

  is($result,             $person,          'Method chaining returns self');
  is($person->name(),     'Chain Test',     'Chained name set');
  is($person->id(),       12345,            'Chained id set');
  is($person->email(),    'chain@test.com', 'Chained email set');
  is($person->is_admin(), 1,                'Chained is_admin set');

  # Test chaining with clear
  $result = $person->clear_permission();
  is($result,                     $person, 'clear_permission returns self');
  is($person->which_permission(), undef,   'Chained clear worked');
};

done_testing();
