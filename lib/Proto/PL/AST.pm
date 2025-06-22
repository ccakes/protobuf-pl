package Proto::PL::AST::Node;

use strict;
use warnings;

# Base class for all AST nodes
sub new {
  my ($class, %args) = @_;
  return bless \%args, $class;
}

# Immutable accessor generation
sub _accessor {
  my ($class, $name) = @_;
  no strict 'refs';
  *{"${class}::${name}"} = sub { $_[0]->{$name} };
}

package Proto::PL::AST::File;
our @ISA = qw(Proto::PL::AST::Node);

__PACKAGE__->_accessor('filename');
__PACKAGE__->_accessor('package');
__PACKAGE__->_accessor('syntax');
__PACKAGE__->_accessor('imports');
__PACKAGE__->_accessor('messages');
__PACKAGE__->_accessor('enums');
__PACKAGE__->_accessor('options');
__PACKAGE__->_accessor('imported_files');

sub new {
  my ($class, %args) = @_;
  $args{imports}        ||= [];
  $args{messages}       ||= [];
  $args{enums}          ||= [];
  $args{options}        ||= {};
  $args{imported_files} ||= {};
  return $class->SUPER::new(%args);
}

sub find_message {
  my ($self, $name) = @_;
  for my $msg (@{$self->messages}) {
    return $msg if $msg->name eq $name;
  }
  return undef;
}

sub find_enum {
  my ($self, $name) = @_;
  for my $enum (@{$self->enums}) {
    return $enum if $enum->name eq $name;
  }
  return undef;
}

sub add_imported_file {
  my ($self, $imported_file) = @_;
  $self->{imported_files}{$imported_file->filename} = $imported_file;
}

sub get_imported_file {
  my ($self, $filename) = @_;
  return $self->{imported_files}{$filename};
}

sub get_all_imported_files {
  my ($self) = @_;
  return values %{$self->{imported_files}};
}

sub find_message_with_imports {
  my ($self, $name) = @_;

  # First check local messages
  my $local_msg = $self->find_message($name);
  return $local_msg if $local_msg;

  # Then check imported files
  for my $imported_file (values %{$self->{imported_files}}) {
    my $imported_msg = $imported_file->find_message_with_imports($name);
    return $imported_msg if $imported_msg;
  }

  return undef;
}

sub find_enum_with_imports {
  my ($self, $name) = @_;

  # First check local enums
  my $local_enum = $self->find_enum($name);
  return $local_enum if $local_enum;

  # Then check imported files
  for my $imported_file (values %{$self->{imported_files}}) {
    my $imported_enum = $imported_file->find_enum_with_imports($name);
    return $imported_enum if $imported_enum;
  }

  return undef;
}

sub resolve_type {
  my ($self, $type_name) = @_;

  # First try direct lookup (works for both simple and qualified names)
  my $message = $self->find_message_with_imports($type_name);
  return $message if $message;

  my $enum = $self->find_enum_with_imports($type_name);
  return $enum if $enum;

  # For qualified names, also try looking in imported files by package
  if ($type_name =~ /\./) {
    return $self->_resolve_qualified_type($type_name);
  }

  return undef;
}

sub _resolve_qualified_type {
  my ($self, $qualified_name) = @_;

  # Split into package and type name
  my @parts     = split /\./, $qualified_name;
  my $type_name = pop @parts;
  my $package   = join('.', @parts);

  # Search in files with matching package
  for my $imported_file (values %{$self->{imported_files}}) {
    next unless $imported_file->package && $imported_file->package eq $package;

    my $message = $imported_file->find_message($type_name);
    return $message if $message;

    my $enum = $imported_file->find_enum($type_name);
    return $enum if $enum;
  }

  return undef;
} ## end sub _resolve_qualified_type

package Proto::PL::AST::Message;
our @ISA = qw(Proto::PL::AST::Node);

__PACKAGE__->_accessor('name');
__PACKAGE__->_accessor('fields');
__PACKAGE__->_accessor('oneofs');
__PACKAGE__->_accessor('options');
__PACKAGE__->_accessor('parent');

sub new {
  my ($class, %args) = @_;
  $args{fields}          ||= [];
  $args{oneofs}          ||= [];
  $args{options}         ||= {};
  return $class->SUPER::new(%args);
}

sub find_field {
  my ($self, $name_or_number) = @_;
  for my $field (@{$self->fields}) {
    return $field if $field->name eq $name_or_number || $field->number == $name_or_number;
  }
  return undef;
}

sub qualified_name {
  my ($self) = @_;

  my $qualified_name = $self->name;
  my $ptr = $self;
  while (defined $ptr->parent) {
    $qualified_name = $ptr->parent->name . '.' . $qualified_name;
    $ptr = $ptr->parent;
  }

  return $qualified_name;
}

sub perl_package_name {
  my ($self, $base_package) = @_;
  my $full_name = $self->qualified_name;  # Use name directly since it's already qualified
  $full_name =~ s/\./::/g;
  return $base_package ? "${base_package}::${full_name}" : $full_name;
}

package Proto::PL::AST::Field;
our @ISA = qw(Proto::PL::AST::Node);

__PACKAGE__->_accessor('name');
__PACKAGE__->_accessor('number');
__PACKAGE__->_accessor('type');
__PACKAGE__->_accessor('label');    # optional, repeated, or undef for singular
__PACKAGE__->_accessor('default_value');
__PACKAGE__->_accessor('options');
__PACKAGE__->_accessor('oneof');

sub new {
  my ($class, %args) = @_;
  $args{options} ||= {};
  return $class->SUPER::new(%args);
}

sub is_repeated {
  my ($self) = @_;
  return ($self->label || '') eq 'repeated';
}

sub is_optional {
  my ($self) = @_;
  return ($self->label || '') eq 'optional';
}

sub is_map {
  my ($self) = @_;
  return $self->type && ref($self->type) eq 'Proto::PL::AST::MapType';
}

sub is_message {
  my ($self) = @_;
  return $self->type && ref($self->type) eq 'Proto::PL::AST::MessageType';
}

sub is_enum {
  my ($self) = @_;
  return $self->type && ref($self->type) eq 'Proto::PL::AST::EnumType';
}

sub is_scalar {
  my ($self) = @_;
  return $self->type && ref($self->type) eq 'Proto::PL::AST::ScalarType';
}

sub wire_type {
  my ($self) = @_;
  return $self->type->wire_type if $self->type;
  return 0;    # varint default
}

sub is_packed {
  my ($self) = @_;
  return 0 unless $self->is_repeated;
  return 1 if $self->options->{packed};

  # Proto3 default: packed for scalar numeric types
  return $self->is_scalar && $self->type->is_numeric;
}

package Proto::PL::AST::Enum;
our @ISA = qw(Proto::PL::AST::Node);

__PACKAGE__->_accessor('name');
__PACKAGE__->_accessor('values');
__PACKAGE__->_accessor('options');
__PACKAGE__->_accessor('parent');

sub new {
  my ($class, %args) = @_;
  $args{values}  ||= [];
  $args{options} ||= {};
  return $class->SUPER::new(%args);
}

sub find_value {
  my ($self, $name_or_number) = @_;
  for my $value (@{$self->values}) {
    return $value if $value->name eq $name_or_number || $value->number == $name_or_number;
  }
  return undef;
}

sub qualified_name {
  my ($self) = @_;

  my $qualified_name = $self->name;
  my $ptr = $self;
  while (defined $ptr->parent) {
    $qualified_name = $ptr->parent->name . '.' . $qualified_name;
    $ptr = $ptr->parent;
  }

  return $qualified_name;
}

sub perl_package_name {
  my ($self, $base_package) = @_;
  my $full_name = $self->qualified_name;  # Use name directly since it's already qualified
  $full_name =~ s/\./::/g;
  return $base_package ? "${base_package}::${full_name}" : $full_name;
}

package Proto::PL::AST::EnumValue;
our @ISA = qw(Proto::PL::AST::Node);

__PACKAGE__->_accessor('name');
__PACKAGE__->_accessor('number');
__PACKAGE__->_accessor('options');

sub new {
  my ($class, %args) = @_;
  $args{options} ||= {};
  return $class->SUPER::new(%args);
}

package Proto::PL::AST::Oneof;
our @ISA = qw(Proto::PL::AST::Node);

__PACKAGE__->_accessor('name');
__PACKAGE__->_accessor('fields');
__PACKAGE__->_accessor('options');

sub new {
  my ($class, %args) = @_;
  $args{fields}  ||= [];
  $args{options} ||= {};
  return $class->SUPER::new(%args);
}

# Type classes
package Proto::PL::AST::Type;
our @ISA = qw(Proto::PL::AST::Node);

sub wire_type  {0}    # varint default
sub is_numeric {0}

package Proto::PL::AST::ScalarType;
our @ISA = qw(Proto::PL::AST::Type);

__PACKAGE__->_accessor('name');

my %WIRE_TYPES = (
  'double'   => 1,    # 64-bit
  'float'    => 5,    # 32-bit
  'int32'    => 0,    # varint
  'int64'    => 0,    # varint
  'uint32'   => 0,    # varint
  'uint64'   => 0,    # varint
  'sint32'   => 0,    # varint (zigzag)
  'sint64'   => 0,    # varint (zigzag)
  'fixed32'  => 5,    # 32-bit
  'fixed64'  => 1,    # 64-bit
  'sfixed32' => 5,    # 32-bit
  'sfixed64' => 1,    # 64-bit
  'bool'     => 0,    # varint
  'string'   => 2,    # length-delimited
  'bytes'    => 2,    # length-delimited
);

my %NUMERIC_TYPES = map { $_ => 1 } qw(
  double float int32 int64 uint32 uint64 sint32 sint64
  fixed32 fixed64 sfixed32 sfixed64 bool
);

sub wire_type {
  my ($self) = @_;
  return $WIRE_TYPES{$self->name} || 0;
}

sub is_numeric {
  my ($self) = @_;
  return $NUMERIC_TYPES{$self->name} || 0;
}

sub is_zigzag {
  my ($self) = @_;
  return $self->name =~ /^sint/;
}

package Proto::PL::AST::MessageType;
our @ISA = qw(Proto::PL::AST::Type);

__PACKAGE__->_accessor('name');
__PACKAGE__->_accessor('message');    # reference to actual message

sub wire_type {2}                     # length-delimited

package Proto::PL::AST::EnumType;
our @ISA = qw(Proto::PL::AST::Type);

__PACKAGE__->_accessor('name');
__PACKAGE__->_accessor('enum');       # reference to actual enum

sub wire_type  {0}                    # varint
sub is_numeric {1}

package Proto::PL::AST::MapType;
our @ISA = qw(Proto::PL::AST::Type);

__PACKAGE__->_accessor('key_type');
__PACKAGE__->_accessor('value_type');

sub wire_type {2}                     # length-delimited (maps are encoded as repeated message)

1;

__END__

=head1 NAME

Proto::PL::AST - Abstract Syntax Tree classes for Protocol Buffers

=head1 SYNOPSIS

    use Proto::PL::AST;
    
    # Create AST nodes (typically done by the parser)
    my $file = Proto::PL::AST::File->new(
        filename => 'test.proto',
        package => 'test',
        syntax => 'proto3',
    );

=head1 DESCRIPTION

This module provides immutable AST node classes for representing
parsed Protocol Buffer schemas. The classes include:

=over 4

=item * File - represents a .proto file

=item * Message - represents a message definition

=item * Field - represents a field within a message

=item * Enum - represents an enum definition

=item * EnumValue - represents a value within an enum

=item * Various Type classes for field types

=back

=head1 AUTHOR

Generated by pl_protoc

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
