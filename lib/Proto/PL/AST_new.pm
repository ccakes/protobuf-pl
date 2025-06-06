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

sub new {
    my ($class, %args) = @_;
    $args{imports} ||= [];
    $args{messages} ||= [];
    $args{enums} ||= [];
    $args{options} ||= {};
    return $class->SUPER::new(%args);
}

sub find_message {
    my ($self, $name) = @_;
    for my $msg (@{$self->messages}) {
        return $msg if $msg->name eq $name;
        # Check nested messages
        if (my $nested = $msg->find_nested_message($name)) {
            return $nested;
        }
    }
    return undef;
}

sub find_enum {
    my ($self, $name) = @_;
    for my $enum (@{$self->enums}) {
        return $enum if $enum->name eq $name;
    }
    # Check nested enums in messages
    for my $msg (@{$self->messages}) {
        if (my $nested = $msg->find_nested_enum($name)) {
            return $nested;
        }
    }
    return undef;
}

package Proto::PL::AST::Message;
our @ISA = qw(Proto::PL::AST::Node);

__PACKAGE__->_accessor('name');
__PACKAGE__->_accessor('fields');
__PACKAGE__->_accessor('nested_messages');
__PACKAGE__->_accessor('nested_enums');
__PACKAGE__->_accessor('oneofs');
__PACKAGE__->_accessor('options');
__PACKAGE__->_accessor('parent');

sub new {
    my ($class, %args) = @_;
    $args{fields} ||= [];
    $args{nested_messages} ||= [];
    $args{nested_enums} ||= [];
    $args{oneofs} ||= [];
    $args{options} ||= {};
    return $class->SUPER::new(%args);
}

sub find_field {
    my ($self, $name_or_number) = @_;
    for my $field (@{$self->fields}) {
        return $field if $field->name eq $name_or_number || $field->number == $name_or_number;
    }
    return undef;
}

sub find_nested_message {
    my ($self, $name) = @_;
    for my $msg (@{$self->nested_messages}) {
        return $msg if $msg->name eq $name;
        # Recursively search in nested messages
        if (my $nested = $msg->find_nested_message($name)) {
            return $nested;
        }
    }
    return undef;
}

sub find_nested_enum {
    my ($self, $name) = @_;
    for my $enum (@{$self->nested_enums}) {
        return $enum if $enum->name eq $name;
    }
    # Recursively search in nested messages
    for my $msg (@{$self->nested_messages}) {
        if (my $nested = $msg->find_nested_enum($name)) {
            return $nested;
        }
    }
    return undef;
}

sub full_name {
    my ($self) = @_;
    my @parts = ($self->name);
    my $parent = $self->parent;
    while ($parent && $parent->isa('Proto::PL::AST::Message')) {
        unshift @parts, $parent->name;
        $parent = $parent->parent;
    }
    return join('.', @parts);
}

sub perl_package_name {
    my ($self, $base_package) = @_;
    my $full_name = $self->full_name;
    $full_name =~ s/\./::/g;
    return $base_package ? "${base_package}::${full_name}" : $full_name;
}

package Proto::PL::AST::Field;
our @ISA = qw(Proto::PL::AST::Node);

__PACKAGE__->_accessor('name');
__PACKAGE__->_accessor('number');
__PACKAGE__->_accessor('type');
__PACKAGE__->_accessor('label');  # optional, repeated, or undef for singular
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
    return 0;  # varint default
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
    $args{values} ||= [];
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

sub full_name {
    my ($self) = @_;
    my @parts = ($self->name);
    my $parent = $self->parent;
    while ($parent && $parent->isa('Proto::PL::AST::Message')) {
        unshift @parts, $parent->name;
        $parent = $parent->parent;
    }
    return join('.', @parts);
}

sub perl_package_name {
    my ($self, $base_package) = @_;
    my $full_name = $self->full_name;
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
    $args{fields} ||= [];
    $args{options} ||= {};
    return $class->SUPER::new(%args);
}

# Type classes
package Proto::PL::AST::Type;
our @ISA = qw(Proto::PL::AST::Node);

sub wire_type { 0 }  # varint default
sub is_numeric { 0 }

package Proto::PL::AST::ScalarType;
our @ISA = qw(Proto::PL::AST::Type);

__PACKAGE__->_accessor('name');

my %WIRE_TYPES = (
    'double'   => 1,  # 64-bit
    'float'    => 5,  # 32-bit
    'int32'    => 0,  # varint
    'int64'    => 0,  # varint
    'uint32'   => 0,  # varint
    'uint64'   => 0,  # varint
    'sint32'   => 0,  # varint (zigzag)
    'sint64'   => 0,  # varint (zigzag)
    'fixed32'  => 5,  # 32-bit
    'fixed64'  => 1,  # 64-bit
    'sfixed32' => 5,  # 32-bit
    'sfixed64' => 1,  # 64-bit
    'bool'     => 0,  # varint
    'string'   => 2,  # length-delimited
    'bytes'    => 2,  # length-delimited
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
__PACKAGE__->_accessor('message');  # reference to actual message

sub wire_type { 2 }  # length-delimited

package Proto::PL::AST::EnumType;
our @ISA = qw(Proto::PL::AST::Type);

__PACKAGE__->_accessor('name');
__PACKAGE__->_accessor('enum');  # reference to actual enum

sub wire_type { 0 }  # varint
sub is_numeric { 1 }

package Proto::PL::AST::MapType;
our @ISA = qw(Proto::PL::AST::Type);

__PACKAGE__->_accessor('key_type');
__PACKAGE__->_accessor('value_type');

sub wire_type { 2 }  # length-delimited (maps are encoded as repeated message)

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
