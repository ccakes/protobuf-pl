#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";

use Example::Person;
use Example::Status;

# Test basic Person construction and field accessors
subtest 'Basic Person construction and accessors' => sub {
  my $person = Example::Person->new();
  isa_ok($person, 'Example::Person');
  isa_ok($person, 'Proto::PL::Runtime::Message');

  # Test string fields
  is($person->name('John Doe'), $person,    'name setter returns self');
  is($person->name(),           'John Doe', 'name getter works');

  is($person->email('john@example.com'), $person,            'email setter returns self');
  is($person->email(),                   'john@example.com', 'email getter works');

  # Test numeric field
  is($person->id(12345), $person, 'id setter returns self');
  is($person->id(),      12345,   'id getter works');

  # Test repeated field - phones
  my $phone1 = Example::Person::PhoneNumber->new();
  $phone1->number('555-1234');
  $phone1->type(Example::Person::PhoneType::HOME);

  my $phone2 = Example::Person::PhoneNumber->new();
  $phone2->number('555-5678');
  $phone2->type(Example::Person::PhoneType::MOBILE);

  my $phones = [ $phone1, $phone2 ];
  is($person->phones($phones), $person, 'phones setter returns self');
  is_deeply($person->phones(), $phones, 'phones getter works');

  # Test map field - attributes
  my $attrs = {'department' => 'Engineering', 'location' => 'NYC'};
  is($person->attributes($attrs), $person, 'attributes setter returns self');
  is_deeply($person->attributes(), $attrs, 'attributes getter works');
};

# Test oneof field behavior - is_admin
subtest 'Oneof field - is_admin' => sub {
  my $person = Example::Person->new();

  # Test setting is_admin
  is($person->is_admin(1),        $person,    'is_admin setter returns self');
  is($person->is_admin(),         1,          'is_admin getter works');
  is($person->which_permission(), 'is_admin', 'which_permission returns is_admin');
  ok($person->has_is_admin(),     'has_is_admin returns true');
  ok(!$person->has_permissions(), 'has_permissions returns false');

  # Test clearing oneof
  is($person->clear_permission(), $person, 'clear_permission returns self');
  is($person->which_permission(), undef,   'which_permission returns undef after clear');
  ok(!$person->has_is_admin(),    'has_is_admin returns false after clear');
  ok(!$person->has_permissions(), 'has_permissions returns false after clear');
};

# Test oneof field behavior - permissions
subtest 'Oneof field - permissions' => sub {
  my $person = Example::Person->new();

  # Test setting permissions
  my $perms = [ 'read', 'write', 'admin' ];
  is($person->permissions($perms), $person, 'permissions setter returns self');
  is_deeply($person->permissions(), $perms, 'permissions getter works');
  is($person->which_permission(), 'permissions', 'which_permission returns permissions');
  ok(!$person->has_is_admin(),   'has_is_admin returns false');
  ok($person->has_permissions(), 'has_permissions returns true');

  # Test clearing oneof
  is($person->clear_permission(), $person, 'clear_permission returns self');
  is($person->which_permission(), undef,   'which_permission returns undef after clear');
  ok(!$person->has_is_admin(),    'has_is_admin returns false after clear');
  ok(!$person->has_permissions(), 'has_permissions returns false after clear');
};

# Test oneof mutual exclusion
subtest 'Oneof mutual exclusion' => sub {
  my $person = Example::Person->new();

  # Set is_admin first
  $person->is_admin(1);
  is($person->which_permission(), 'is_admin', 'is_admin is set');
  ok($person->has_is_admin(), 'has_is_admin returns true');

  # Now set permissions - should clear is_admin
  $person->permissions([ 'read', 'write' ]);
  is($person->which_permission(), 'permissions', 'permissions is now set');
  ok($person->has_permissions(), 'has_permissions returns true');
  ok(!$person->has_is_admin(),   'has_is_admin returns false - was cleared');
  is($person->is_admin(), undef, 'is_admin value is cleared');

  # Set is_admin again - should clear permissions
  $person->is_admin(0);
  is($person->which_permission(), 'is_admin', 'is_admin is set again');
  ok($person->has_is_admin(),     'has_is_admin returns true');
  ok(!$person->has_permissions(), 'has_permissions returns false - was cleared');
  is_deeply($person->permissions(), undef, 'permissions value is cleared');
};

# Test PhoneNumber sub-message
subtest 'PhoneNumber sub-message' => sub {
  my $phone = Example::Person::PhoneNumber->new();
  isa_ok($phone, 'Example::Person::PhoneNumber');
  isa_ok($phone, 'Proto::PL::Runtime::Message');

  is($phone->number('555-1234'), $phone,     'number setter returns self');
  is($phone->number(),           '555-1234', 'number getter works');

  is($phone->type(Example::Person::PhoneType::WORK), $phone,                           'type setter returns self');
  is($phone->type(),                                 Example::Person::PhoneType::WORK, 'type getter works');
};

# Test PhoneType enum
subtest 'PhoneType enum constants' => sub {
  is(Example::Person::PhoneType::MOBILE, 0, 'MOBILE constant');
  is(Example::Person::PhoneType::HOME,   1, 'HOME constant');
  is(Example::Person::PhoneType::WORK,   2, 'WORK constant');
};

# Test Status enum
subtest 'Status enum constants' => sub {
  is(Example::Status::UNKNOWN,  0, 'UNKNOWN constant');
  is(Example::Status::ACTIVE,   1, 'ACTIVE constant');
  is(Example::Status::INACTIVE, 2, 'INACTIVE constant');
};

# Test constructor with initial values
subtest 'Constructor with initial values' => sub {
  my $phone = Example::Person::PhoneNumber->new(
    number => '555-9999',
    type   => Example::Person::PhoneType::MOBILE
  );

  is($phone->number(), '555-9999',                         'constructor set number');
  is($phone->type(),   Example::Person::PhoneType::MOBILE, 'constructor set type');

  my $person = Example::Person->new(
    name       => 'Jane Doe',
    id         => 54321,
    email      => 'jane@example.com',
    phones     => [$phone],
    attributes => {'role' => 'manager'},
    is_admin   => 1
  );

  is($person->name(),                  'Jane Doe',         'constructor set name');
  is($person->id(),                    54321,              'constructor set id');
  is($person->email(),                 'jane@example.com', 'constructor set email');
  is(scalar(@{$person->phones()}),     1,                  'constructor set phones array');
  is($person->phones()->[0]->number(), '555-9999',         'constructor set phone details');
  is_deeply($person->attributes(), {'role' => 'manager'}, 'constructor set attributes');
  is($person->is_admin(),         1,          'constructor set is_admin');
  is($person->which_permission(), 'is_admin', 'constructor set oneof correctly');
};

done_testing();
